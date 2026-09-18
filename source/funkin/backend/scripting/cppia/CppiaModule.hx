package funkin.backend.scripting.cppia;

/* the cppia interpreter is only compiled into the host under -D scriptable, #if cpp alone would fail to link NO_SCRIPTABLE builds */
#if (cpp && scriptable)
import cpp.cppia.Module;
import funkin.backend.system.Logs;
import funkin.backend.utils.NativeAPI.ConsoleColor;
import lime.utils.Assets as LimeAssets;

/* cpp.cppia.Module expands to hx::CppiaLoadedModule, declared in hx/Scriptable.h which generated headers don't include on their own */
@:headerCode('#include <hx/Scriptable.h>')
class CppiaModule
{
	private static var __modules:Map<String, Module> = [];
	// modules can't be unloaded, so failed loads are remembered to avoid re-parsing and double-registering classes
	private static var __failedModules:Map<String, String> = [];

	public static function load(assetPath:String):Module
	{
		if (__modules.exists(assetPath))
			return __modules.get(assetPath);
		if (__failedModules.exists(assetPath))
			return null;

		try {
			if (!LimeAssets.exists(assetPath))
				return null;

			var module = Module.fromData(LimeAssets.getBytes(assetPath).getData());
			// boot registers classes and runs __init__ (one-shot, even on failure); run() is never called, so a -main entry stays dormant
			module.boot();
			__modules.set(assetPath, module);
			return module;
		} catch(e) {
			var reason = Std.string(e);
			__failedModules.set(assetPath, reason);
			Logs.traceColored([
				Logs.logText(assetPath, GREEN),
				Logs.logText('Error while loading cppia module: $reason', RED)
			], ERROR);
			return null;
		}
	}

	public static function resolve(assetPath:String, className:String):Class<Dynamic>
	{
		var module = load(assetPath);
		if (module == null)
			return null;

		return module.resolveClass(className);
	}

	// modules can't actually be unloaded, this only drops our references
	public static function clearCache():Void
	{
		__modules = [];
		__failedModules = [];
	}
}
#end
