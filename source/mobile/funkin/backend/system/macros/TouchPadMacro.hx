package mobile.funkin.backend.system.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.xml.Parser;
import sys.io.File;
import sys.FileSystem;

class TouchPadMacro
{
	public static final GRAPHICS_IGNORE:Array<String> = ['bg.png'];

	public static macro function build():Array<Field>
	{
		final pos:Position = Context.currentPos();
		final fields:Array<Field> = Context.getBuildFields();
		final newFields:Array<Field> = [];

		for (graphic in getGraphicsList())
		{
			if (GRAPHICS_IGNORE.contains(graphic)) continue;

			var typePath:TypePath = {
				name: 'TouchButton',
				pack: ['mobile', 'objects']
			};

			var args:Array<Expr> = [
				Context.makeExpr(0, pos),
				Context.makeExpr(0, pos),
				Context.makeExpr([graphic.split('.')[0]], pos)
			];

			var expr:Expr = {
				expr: ENew(typePath, args),
				pos: pos
			};

			newFields.push({
				name: formatGraphicToButtonName(graphic),
				access: [APublic],
				kind: FVar(macro :mobile.objects.TouchButton, expr),
				pos: pos,
			});
		}

		return fields.concat(newFields);
	}

	private static function getGraphicsList():Array<String>
	{
		#if ios
		final grapghicsPath:String = "../../../../../assets/mobile/images/touchpad/";
		#else
		final grapghicsPath:String = "assets/mobile/images/touchpad/";
		#end

		if (!FileSystem.exists(grapghicsPath)) Context.error("ERROR: Directory '" + grapghicsPath + "' not found but it's required.", Context.currentPos());

		return FileSystem.readDirectory(grapghicsPath);
	}

	private static function formatGraphicToButtonName(name:String):String
	{
		if (StringTools.contains(name, '.')) name = name.split('.')[0];
		name = name.toLowerCase();
		name = name.charAt(0).toUpperCase() + name.substr(1, name.length);

		return 'button$name';
	}
}
#end
