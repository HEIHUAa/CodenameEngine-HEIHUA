package funkin.backend;

import animate.FlxAnimate;
import animate.FlxAnimateController.FlxAnimateAnimation;
import flixel.addons.effects.FlxSkewedSprite;
import flixel.animation.FlxAnimation;
import flixel.math.FlxMatrix;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.system.FlxAssets.FlxGraphicAsset;
import flixel.system.FlxAssets.FlxShader;
import flixel.util.typeLimit.OneOfTwo;
import funkin.backend.scripting.events.sprite.PlayAnimContext;
import funkin.backend.system.interfaces.IBeatReceiver;
import funkin.backend.system.interfaces.IOffsetCompatible;
import funkin.backend.utils.XMLUtil.AnimData;
import funkin.backend.utils.XMLUtil.BeatAnim;
import funkin.backend.utils.XMLUtil.IXMLEvents;
import haxe.io.Path;
import flixel.graphics.frames.FlxFrame;
import flixel.math.FlxAngle;
import animate.internal.RenderTexture;
import animate.FlxAnimateFrames;

enum abstract XMLAnimType(Int)
{
	var NONE = 0;
	var BEAT = 1;
	var LOOP = 2;

	public static function fromString(str:String, def:XMLAnimType = XMLAnimType.NONE)
	{
		return switch (StringTools.trim(str).toLowerCase())
		{
			case "none": NONE;
			case "beat" | "onbeat": BEAT;
			case "loop": LOOP;
			default: def;
		}
	}

	@:to public function toString():String {
		return switch (cast this)
		{
			case NONE: "none";
			case BEAT: "beat";
			case LOOP: "loop";
		}
	}
}

class FunkinSprite extends FlxAnimate implements IBeatReceiver implements IOffsetCompatible implements IXMLEvents
{
	public var extra:Map<String, Dynamic> = [];

	public var spriteAnimType:XMLAnimType = NONE;
	public var beatAnims:Array<BeatAnim> = [];
	public var name:String;
	public var zoomFactor:Float = 1;
	public var angleFactor:Float = 1;
	public var debugMode:Bool = false;
	public var animDatas:Map<String, AnimData> = [];
	public var animEnabled:Bool = true;
	public var zoomFactorEnabled:Bool = true;
	public var angleFactorEnabled:Bool = true;

	//Backwards compatibility
	public var animateAtlas(get, never):FunkinSprite;

	public var globalCurFrame(get, set):Int;

	/**
	 * ODD interval -> not aligned to beats
	 * EVEN interval -> aligned to beats
	 */
	public var beatInterval(default, set):Int = 2;
	public var beatOffset:Int = 0;
	public var skipNegativeBeats:Bool = false;

	public var animateSettings:FlxAnimateSettings = {};

	// originally used for zoom factor, now unused
	var _rect2:FlxRect;

	public function new(?X:Float = 0, ?Y:Float = 0, ?SimpleGraphic:FlxGraphicAsset)
	{
		super(X, Y);

		if (SimpleGraphic != null)
		{
			if (SimpleGraphic is String)
				loadSprite(cast SimpleGraphic);
			else
				loadGraphic(SimpleGraphic);
		}

		moves = false;
		applyStageMatrix = true;
		postStageMatrixApply = Flags.USE_LEGACY_FLXANIMATE_STAGE_MATRIX;
	}

	/**
	 * Gets the graphics and copies other properties from another sprite (Works both for `FlxSprite` and `FunkinSprite`!).
	 */
	public static function copyFrom(source:FlxSprite):FunkinSprite
	{
		var spr = new FunkinSprite();
		var casted:FunkinSprite = null;
		if (source is FunkinSprite)
			casted = cast source;

		@:privateAccess {
			spr.setPosition(source.x, source.y);
			spr.frames = source.frames;
			spr.animation.copyFrom(source.animation);
			spr.visible = source.visible;
			spr.alpha = source.alpha;
			spr.antialiasing = source.antialiasing;
			spr.scale.set(source.scale.x, source.scale.y);
			spr.scrollFactor.set(source.scrollFactor.x, source.scrollFactor.y);

			if (casted != null) {
				spr.skew.set(casted.skew.x, casted.skew.y);
				for (i => p in casted.animOffsets) spr.addOffset(i, p.x, p.y);
				spr.zoomFactor = casted.zoomFactor;
				spr.angleFactor = casted.angleFactor;
			}
		}
		return spr;
	}

	public override function update(elapsed:Float)
	{
		super.update(elapsed);

		// hate how it looks like but hey at least its optimized and fast  - Nex
		if (!debugMode && isAnimFinished()) {
			var name = getAnimName() + '-loop';
			if (hasAnim(name))
				playAnim(name, null, lastAnimContext);
		}
	}

	override function initVars() {
		super.initVars();
		_rect2 = FlxRect.get();
	}

	public function loadSprite(path:String, Unique:Bool = false, Key:String = null)
	{
		frames = Paths.getFrames(path, true, null, null, animateSettings);
		return this;
	}

	public function onPropertySet(property:String, value:Dynamic) {
		if (property.startsWith("velocity") || property.startsWith("acceleration"))
			moves = true;
	}

	private var countedBeat = 0;
	public function beatHit(curBeat:Int)
	{
		if(!animEnabled) return;
		if (lastAnimContext != LOCK && beatAnims.length > 0 && (curBeat + beatOffset) % beatInterval == 0)
		{
			// TODO: find a solution without countedBeat
			var anim = beatAnims[FlxMath.wrap(countedBeat++, 0, beatAnims.length - 1)];
			if (anim.name != null && anim.name != "null" && anim.name != "none")
				playAnim(anim.name, anim.forced);
		}
	}

	public function stepHit(curBeat:Int)
	{
	}

	public function measureHit(curMeasure:Int)
	{
	}

	public override function draw() {
		// re-implementing the `onDraw` functionality from `FlxSprite` since `FlxAnimate` didn't have this, so we have to add it back in ourselves
	    if (this.isAnimate && this.__drawOverrided) {
	        this.__drawOverrided = false;
	        this.onDraw(this);
	        this.__drawOverrided = true;
			return;
	    }
	    super.draw();
	}

	// ANIMATE ATLAS DRAWING
	#if REGION
	public override function destroy()
	{
		disposeRenderTargets();
		if (animOffsets != null) {
			for (key in animOffsets.keys()) {
				final point = animOffsets[key];
				animOffsets.remove(key);
				if (point != null)
					point.put();
			}
			animOffsets = null;
		}
		super.destroy();

		_rect2 = FlxDestroyUtil.put(_rect2);
		_chainBounds = FlxDestroyUtil.put(_chainBounds);
	}
	#end

	// OFFSETTING
	#if REGION
	public var animOffsets:Map<String, FlxPoint> = new Map<String, FlxPoint>();

	public function addOffset(name:String, x:Float = 0, y:Float = 0)
	{
		animOffsets[name] = FlxPoint.get(x, y);
	}

	public function switchOffset(anim1:String, anim2:String)
	{
		var old = animOffsets[anim1];
		animOffsets[anim1] = animOffsets[anim2];
		animOffsets[anim2] = old;
	}
	#end

	// PLAYANIM
	#if REGION
	public var lastAnimContext:PlayAnimContext = DANCE;

	public function playAnim(AnimName:String, ?Force:Null<Bool>, Context:PlayAnimContext = NONE, Reversed:Bool = false, Frame:Int = 0):Void
	{
		if (AnimName == null || (!hasAnim(AnimName) && !debugMode))
			return;

		if (Force == null) {
			var anim = animDatas.get(AnimName);
			Force = anim != null && anim.forced;
		}

		animation.play(AnimName, Force, Reversed, Frame);

		var daOffset = getAnimOffset(AnimName);
		frameOffset.set(daOffset.x, daOffset.y);
		daOffset.putWeak();

		lastAnimContext = Context;
	}

	public inline function addAnim(name:String, prefix:String, frameRate:Float = 24, ?looped:Bool, ?forced:Bool, ?indices:Array<Int>, x:Float = 0, y:Float = 0, animType:XMLAnimType = NONE, animateAtlasLabel:Bool = false)
	{
		return XMLUtil.addAnimToSprite(this, {
			name: name,
			anim: prefix,
			fps: frameRate,
			loop: looped == null ? animType == LOOP : looped,
			animType: animType,
			x: x,
			y: y,
			indices: indices,
			forced: forced,
			label: animateAtlasLabel
		});
	}

	public inline function removeAnim(name:String) {
		animation.remove(name);
	}

	public function getAnim(name:String):OneOfTwo<FlxAnimation, FlxAnimateAnimation> {
		return animation.getByName(name);
	}

	public inline function getAnimOffset(name:String)
	{
		if (animOffsets.exists(name))
			return animOffsets[name];
		return FlxPoint.weak(0, 0);
	}

	public inline function hasAnim(AnimName:String):Bool
		return animation.exists(AnimName);

	public inline function getAnimName()
		return animation.name;

	public inline function isAnimReversed():Bool
		return animation.curAnim?.reversed ?? false;

	public inline function getNameList():Array<String>
		return animation.getNameList();

	public inline function stopAnim()
		animation.stop();

	public inline function isAnimFinished()
		return animation.curAnim?.finished ?? true;

	public inline function isAnimAtEnd()
		return animation.curAnim?.isAtEnd ?? false;

	override function updateAnimation(elapsed:Float) {
		if (animEnabled)
			super.updateAnimation(elapsed);
	}

	// Backwards compat (the names used to be all different and it sucked, please lets use the same format in the future)  - Nex
	@:dox(hide) public inline function hasAnimation(AnimName:String) return hasAnim(AnimName);
	@:dox(hide) public inline function removeAnimation(name:String) return removeAnim(name);
	@:dox(hide) public inline function stopAnimation() return stopAnim();
	#end

	#if REGION
	/**
	 * Master switch of the multi-shader chain. When `false` (or when `shaders` is empty),
	 * the sprite draws exactly like it would without the chain.
	 */
	public var multiShaderEnabled:Bool = true;

	/**
	 * Only supported on GPU renderers; on `FlxG.renderBlit` the sprite falls back to
	 * the normal drawing path.
	 */
	public var shaders:Array<FlxShader> = [];

	/**
	 * Transparent margin in pixels baked around the sprite content before the chain
	 * runs, settable per side. Effects that push pixels outwards (blur, glow, outlines,
	 * displacement) need this to avoid getting clipped by the sprite bounds.
	 */
	public var shaderPadLeft:Int = 0;
	public var shaderPadRight:Int = 0;
	public var shaderPadTop:Int = 0;
	public var shaderPadBottom:Int = 0;

	/**
	 * Chain render textures are sized in multiples of this, so that the small bounds
	 * changes between animation frames don't constantly allocate new textures.
	 */
	public var shaderBucket:Int = 128;

	/**
	 * Resolution scale of the chain render textures. The sprite content is rendered at
	 * `size * shaderScale` and drawn back at the sprite's normal size, so the on-screen
	 * size stays unchanged while effects run at a higher resolution (`> 1`, supersampled,
	 * sharper) or a lower one (`< 1`, cheaper; with `antialiasing = false` it works as a
	 * pixelation effect). Defaults to `1`.
	 */
	public var shaderScale(default, set):Float = 1;

	function set_shaderScale(v:Float):Float
	{
		if (v <= 0)
			v = 1;
		if (shaderScale != v)
			_renderTextureDirty = true;
		return shaderScale = v;
	}

	public function addShader(s:FlxShader):Void
	{
		if (s != null && shaders.indexOf(s) == -1)
			shaders.push(s);
	}

	public function removeShader(s:FlxShader):Bool
		return shaders.remove(s);

	/**
	 * Frees the offscreen render targets used by the shader chain;
	 * they are recreated as soon as the chain runs again.
	 */
	public function disposeRenderTargets():Void
	{
		_chainRT = FlxDestroyUtil.destroy(_chainRT);
		_chainRT2 = FlxDestroyUtil.destroy(_chainRT2);
		_chainRT3 = FlxDestroyUtil.destroy(_chainRT3);
	}

	inline function chainActive():Bool
		return multiShaderEnabled && shaders.length > 0 && !FlxG.renderBlit;

	inline function bucketSize(size:Int):Int
	{
		if (size < 1)
			return 1;
		final bucket = shaderBucket < 1 ? 1 : shaderBucket;
		final scaled = Math.ceil(size / bucket) * bucket;
		final max = FlxG.bitmap.maxTextureSize;
		return max > 0 && scaled > max ? max : scaled;
	}

	var _chainRT:RenderTexture;
	var _chainRT2:RenderTexture;
	var _chainRT3:RenderTexture;
	var _chainW:Int = 0;
	var _chainH:Int = 0;
	var _chainPadL:Int = 0;
	var _chainPadR:Int = 0;
	var _chainPadT:Int = 0;
	var _chainPadB:Int = 0;
	var _chainScale:Float = 0;
	var _chainBounds:FlxRect;
	var _chainFlattenCb:FlxCamera->FlxMatrix->Void;
	var _chainFlattenFrameCb:FlxCamera->FlxMatrix->Void;
	var _chainFlattenFrame:FlxFrame;
	var _chainPassCb:FlxCamera->FlxMatrix->Void;
	var _chainPassSrcFrame:FlxFrame;
	var _chainPassShader:FlxShader;
	var _chainFrameMat:FlxMatrix;

	function ensureChainRTs():Void
	{
		if (_chainRT != null)
			return;
		_chainRT = new RenderTexture(_chainW, _chainH);
		_chainRT2 = new RenderTexture(_chainW, _chainH);
		_chainRT3 = new RenderTexture(_chainW, _chainH);
		_chainFlattenCb = chainFlattenDraw;
		_chainFlattenFrameCb = chainFlattenFrameDraw;
		_chainPassCb = chainPassDraw;
		_chainFrameMat = new FlxMatrix();
		_renderTextureDirty = true;
	}

	function runChainPass(src:RenderTexture, dst:RenderTexture, s:FlxShader):Void
	{
		dst.init(_chainW, _chainH);
		_chainPassSrcFrame = src.graphic.imageFrame.frame;
		_chainPassShader = s;
		dst.drawToCamera(_chainPassCb);
		dst.render();
	}

	@:privateAccess function chainFlattenDraw(rtCam:FlxCamera, matrix:FlxMatrix):Void
	{
		final bounds = timeline._bounds;
		final scale = shaderScale;
		matrix.identity();
		matrix.scale(scale, scale);
		matrix.translate((shaderPadLeft - bounds.x) * scale, (shaderPadTop - bounds.y) * scale);
		timeline.draw(rtCam, matrix, null, null, antialiasing, null);
	}

	@:privateAccess function chainFlattenFrameDraw(rtCam:FlxCamera, matrix:FlxMatrix):Void
	{
		final frame = _chainFlattenFrame;
		final scale = shaderScale;
		frame.prepareMatrix(matrix, FlxFrameAngle.ANGLE_0, false, false);
		matrix.translate(-frame.offset.x, -frame.offset.y);
		matrix.scale(scale, scale);
		matrix.translate(shaderPadLeft * scale, shaderPadTop * scale);
		rtCam.drawPixels(frame, null, matrix, null, null, antialiasing, null, wrapMode);
	}

	@:privateAccess function chainPassDraw(rtCam:FlxCamera, matrix:FlxMatrix):Void
	{
		matrix.identity();
		rtCam.drawPixels(_chainPassSrcFrame, null, matrix, null, null, antialiasing, _chainPassShader, wrapMode);
	}

	function runChainAndComposite(camera:FlxCamera, matrix:FlxMatrix):Void
	{
		var src = _chainRT;
		var dst = _chainRT2;
		if (shaderEnabled && shader != null)
		{
			runChainPass(src, dst, shader);
			src = dst;
			dst = _chainRT3;
		}
		for (s in shaders)
		{
			if (s == null)
				continue;
			runChainPass(src, dst, s);
			src = dst;
			dst = dst == _chainRT2 ? _chainRT3 : _chainRT2;
		}

		final frame = src.graphic.imageFrame.frame;
		if (layer != null)
			layer.drawPixels(this, camera, frame, framePixels, matrix, colorTransform, blend, antialiasing, null, wrapMode);
		else
			camera.drawPixels(frame, framePixels, matrix, colorTransform, blend, antialiasing, null, wrapMode);
	}

	override function drawAnimate(camera:FlxCamera):Void
	{
		if (!chainActive())
		{
			super.drawAnimate(camera);
			return;
		}

		final padL = shaderPadLeft;
		final padR = shaderPadRight;
		final padT = shaderPadTop;
		final padB = shaderPadBottom;
		final scale = shaderScale;

		final bounds = @:privateAccess timeline._bounds;
		if (_chainBounds == null)
			_chainBounds = FlxRect.get();
		_chainBounds.set(bounds.x - padL, bounds.y - padT,
			bounds.width + padL + padR, bounds.height + padT + padB);

		_chainW = bucketSize(Math.ceil(_chainBounds.width * scale));
		_chainH = bucketSize(Math.ceil(_chainBounds.height * scale));
		ensureChainRTs();
		if (_chainPadL != padL || _chainPadR != padR || _chainPadT != padT || _chainPadB != padB || _chainScale != scale)
		{
			_chainPadL = padL;
			_chainPadR = padR;
			_chainPadT = padT;
			_chainPadB = padB;
			_chainScale = scale;
			_renderTextureDirty = true;
		}

		final matrix = _matrix;
		matrix.identity();
		matrix.scale(1 / scale, 1 / scale);
		matrix.translate(-padL, -padT);
		prepareAnimateMatrix(matrix, camera, _chainBounds);

		if (renderStage)
			drawStage(camera);

		timeline.currentFrame = animation.frameIndex;

		if (!useRenderTexture)
			useRenderTexture = true;
		if (_renderTextureDirty)
		{
			_chainRT.init(_chainW, _chainH);
			_chainRT.drawToCamera(_chainFlattenCb);
			_chainRT.render();
			_renderTextureDirty = false;
		}

		runChainAndComposite(camera, matrix);
	}

	override function drawFrameComplex(frame:FlxFrame, camera:FlxCamera):Void
	{
		if (!chainActive())
		{
			super.drawFrameComplex(frame, camera);
			return;
		}

		final padL = shaderPadLeft;
		final padR = shaderPadRight;
		final padT = shaderPadTop;
		final padB = shaderPadBottom;
		final scale = shaderScale;

		_chainW = bucketSize(Math.ceil((frame.sourceSize.x + padL + padR) * scale));
		_chainH = bucketSize(Math.ceil((frame.sourceSize.y + padT + padB) * scale));
		ensureChainRTs();

		_chainFlattenFrame = frame;
		_chainRT.init(_chainW, _chainH);
		_chainRT.drawToCamera(_chainFlattenFrameCb);
		_chainRT.render();

		final matrix = _matrix;
		matrix.identity();
		matrix.scale(1 / scale, 1 / scale);
		matrix.translate(-padL, -padT);
		final flipX = checkFlipX();
		final flipY = checkFlipY();
		_chainFrameMat.identity();
		_chainFrameMat.scale(flipX ? -1 : 1, flipY ? -1 : 1);
		_chainFrameMat.translate(
			flipX ? Std.int(frame.sourceSize.x) - frame.offset.x : frame.offset.x,
			flipY ? Std.int(frame.sourceSize.y) - frame.offset.y : frame.offset.y
		);
		matrix.concat(_chainFrameMat);
		prepareDrawMatrix(matrix, camera);

		runChainAndComposite(camera, matrix);
	}
	#end

	// Getter / Setters

	@:noCompletion private function set_beatInterval(v:Int) {
		if (v < 1)
			v = 1;

		return beatInterval = v;
	}

	@:noCompletion
	@:deprecated("`FunkinSprite.animateAtlas` is deprecated, just use `FunkinSprite` instead")
	public function get_animateAtlas():FunkinSprite
    	return isAnimate ? this : null;

	@:noCompletion private inline function get_globalCurFrame()
		return animation.curAnim?.curFrame ?? 0;

	@:noCompletion private inline function set_globalCurFrame(val:Int) {
		if (animation.curAnim != null)
			animation.curAnim.curFrame = val;
		return val;
	}

    override function prepareDrawMatrix(matrix:FlxMatrix, camera:FlxCamera):Void {
		super.prepareDrawMatrix(matrix, camera);

		final ox = camera.width * 0.5, oy = camera.height * 0.5;
		final sx = (camera.scaleX > 0.0 ? Math.max : Math.min)(0.0, (1.0 - zoomFactor) / camera.scaleX + zoomFactor);
		final sy = (camera.scaleY > 0.0 ? Math.max : Math.min)(0.0, (1.0 - zoomFactor) / camera.scaleY + zoomFactor);

		if (zoomFactorEnabled && zoomFactor != 1) {
			matrix.setTo(
				matrix.a * sx, matrix.b * sy,
				matrix.c * sx, matrix.d * sy,
				(matrix.tx - ox) * sx + ox,
				(matrix.ty - oy) * sy + oy
			);
		}

		if (angleFactorEnabled && angleFactor != 1) {
			matrix.translate(-ox, -oy);
			matrix.rotate(-camera.angle * FlxAngle.TO_RAD * (1.0 - angleFactor));
			matrix.translate(ox, oy);
		}
	}

	override function checkFlipX() {
		return super.checkFlipX() != camera.flipX;
	}
	override function checkFlipY() {
		return super.checkFlipY() != camera.flipY;
	}
}