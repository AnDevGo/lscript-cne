package lscript;

import lscript.LScript;
import lscript.CustomConvert;

import llua.Lua;
import llua.LuaL;
import llua.State;

import cpp.RawPointer;
import cpp.Callable;

class MetatableFunctions {
	/**
	 * The metatable function that is called when lua tries to get an unknown variable.
	 */
	public static final callIndex = Callable.fromStaticFunction(_callIndex);
	/**
	 * The metatable function that is called when lua tries to set an unknown variable.
	 */
	public static final callNewIndex = Callable.fromStaticFunction(_callNewIndex);
	/**
	 * The metatable function that is called when lua calls a function with this metatable. (Most likely a haxe function)
	 */
	public static final callMetatableCall = Callable.fromStaticFunction(_callMetatableCall);
	/**
	 * The metatable function that is called when lua tries to get an enum value. (TODO: Fix enum values with parameters.)
	 */
	public static final callGarbageCollect = Callable.fromStaticFunction(_callGarbageCollect);
	/**
	 * The metatable function that is called when lua tries to get an enum value. (TODO: Fix enum values with parameters.)
	 */
	public static final callEnumIndex = Callable.fromStaticFunction(_callEnumIndex);
	/**
	 * The metatable function that is called when lua tries to get a global variable.
	 */
	public static final callGlobalIndex = Callable.fromStaticFunction(_callGlobalIndex);
	/**
	 * The metatable function that is called when lua tries to set a global variable.
	 */
	public static final callGlobalNewIndex = Callable.fromStaticFunction(_callGlobalNewIndex);

	//These functions are here because Callable seems like it wants an int return and whines when you do a non static function.
	static function _callIndex(state:StatePointer):Int {
		return metatableFunc(LScript.currentLua.luaState, 0);
	}
	static function _callNewIndex(state:StatePointer):Int {
		return metatableFunc(LScript.currentLua.luaState, 1);
	}
	static function _callMetatableCall(state:StatePointer):Int {
		return metatableFunc(LScript.currentLua.luaState, 2);
	}
	static function _callGarbageCollect(state:StatePointer):Int {
		return metatableFunc(LScript.currentLua.luaState, 3);
	}
	static function _callEnumIndex(state:StatePointer):Int {
		return metatableFunc(LScript.currentLua.luaState, 4);
	}
	static function _callGlobalIndex(state:StatePointer):Int {
		return globalMetatableFunc(LScript.currentLua.luaState, 0);
	}
	static function _callGlobalNewIndex(state:StatePointer):Int {
		return globalMetatableFunc(LScript.currentLua.luaState, 1);
	}

	static function metatableFunc(state:State, funcNum:Int) {
		final functions:Array<Dynamic> = [index, newIndex, metatableCall, garbageCollect, enumIndex];

		//Making the params for the function.
		final nparams:Int = Lua.gettop(state);

		var specialIndex:Int = -1;
		var parentIndex:Int = -1;
		
		final params:Array<Dynamic> = [
			for(i in 0...nparams)
				CustomConvert.fromLua(
					-nparams + i,
					RawPointer.addressOf(specialIndex),
					RawPointer.addressOf(parentIndex),
					i == 0
				)
		];

		if (funcNum == 2) {
			final objParent = (parentIndex >= 0) ? LScript.currentLua.specialVars[parentIndex] : null;
			if (params[1] != objParent)
				params.insert(1, objParent);

			final funcParams = [for (i in 2...params.length) params[i]];
			params.splice(2, params.length);
			params.push(funcParams);
		}

		//Calling the function. If it catches something, will send a lua error of what went wrong.
		var returned:Dynamic = null;
		try {
			returned = functions[funcNum](params[0], params[1], params[2]); //idk why im not using Reflect but this slightly more optimized so whatevs.
		} catch(e) {
			LuaL.error(state, "Lua Metatable Error: " + e.details());
			Lua.settop(state, 0);
			return 0;
		}
		Lua.settop(state, 0);

		if (returned != null) {
			CustomConvert.toLua(returned, funcNum < 2 ? specialIndex : -1);
			return 1;
		}
		return 0;
	}

	static function globalMetatableFunc(state:State, funcNum:Int) {
		// Check if state is valid
		if (state == null) return 0;

		final functions:Array<Dynamic> = [globalIndex, globalNewIndex];

		// Get parameters safely
		var returned:Dynamic = null;
		try {
			final nparams:Int = Lua.gettop(state);
			if (nparams < 2) {
				Lua.settop(state, 0);
				return 0;
			}

			final params:Array<Dynamic> = [for(i in 0...nparams) CustomConvert.fromLua(-nparams + i)];

			// Call the function safely
			if (LScript.currentLua != null && LScript.GlobalVars != null) {
				returned = functions[funcNum](params[1], params[2]); // params[0] is the global table itself
			}
		} catch(e) {
			try {
				LuaL.error(state, "Global Variable Error: " + e.details());
			} catch(e2) {
				// If even error reporting fails, just clean up
			}
			Lua.settop(state, 0);
			return 0;
		}

		Lua.settop(state, 0);

		if (returned != null) {
			try {
				CustomConvert.toLua(returned);
				return 1;
			} catch(e) {
				return 0;
			}
		}
		return 0;
	}

	//These three functions are the actual functions that the metatable use.
	//Without these, object oriented lua wouldn't work at all.

	public static function index(object:Dynamic, property:Any, ?uselessValue:Any):Dynamic {
		if (object is Array && property is Int)
			return object[cast(property, Int)];

		var grabbedProperty:Dynamic = null;
		var propName:String = cast(property, String);

		if (object != null && (grabbedProperty = Reflect.getProperty(object, propName)) != null)
			return grabbedProperty;
		return null;
	}
	public static function newIndex(object:Dynamic, property:Any, value:Dynamic) {
		if (object is Array && property is Int) {
			object[cast(property, Int)] = value;
			return null;
		}

		var propName:String = cast(property, String);

		// Check if object is not null before trying to set property
		if (object != null) {
			try {
				// First try to set the property using Reflect
				Reflect.setProperty(object, propName, value);
			} catch (e:Dynamic) {
				// If that fails, try to set it as a dynamic field
				try {
					object.setProperty(propName, value);
				} catch (e2:Dynamic) {
					// If that also fails, try to directly set the field
					try {
						Reflect.setField(object, propName, value);
					} catch (e3:Dynamic) {
						// If all methods fail, we at least tried
					}
				}
			}
		}
		return null;
	}
	public static function metatableCall(func:Dynamic, object:Dynamic, ?params:Array<Any>) {
		final funcParams = (params != null && params.length > 0) ? params : [];

		if (func != null && Reflect.isFunction(func))
			return Reflect.callMethod(object, func, funcParams);
		return null;
	}
	public static function garbageCollect(index:Int) {
		LScript.currentLua.avalibableIndexes.push(index);
		LScript.currentLua.specialVars.remove(index);
	}
	public static function enumIndex(object:Enum<Dynamic>, value:String, ?params:Array<Any>):EnumValue {
		final funcParams = (params != null && params.length > 0) ? params : [];
		var enumValue:EnumValue;

		enumValue = object.createByName(value, funcParams);
		if (object != null && enumValue != null)
			return enumValue;
		return null;
	}

	public static function globalIndex(property:String, ?uselessValue:Dynamic):Dynamic {
		try {
			if (property != null && LScript.GlobalVars != null && LScript.GlobalVars.exists(property)) {
				return LScript.GlobalVars.get(property);
			}
		} catch (e:Dynamic) {
			// Ignore errors during global variable access
		}
		return null;
	}

	public static function globalNewIndex(property:String, value:Dynamic):Dynamic {
		try {
			if (property != null && LScript.GlobalVars != null) {
				LScript.GlobalVars.set(property, value);
			}
		} catch (e:Dynamic) {
			// Ignore errors during global variable setting
		}
		return null;
	}
}
