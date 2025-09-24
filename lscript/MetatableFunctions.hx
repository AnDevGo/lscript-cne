
package lscript;

import lscript.LScript;
import lscript.CustomConvert;
import llua.Lua;
import llua.LuaL;
import llua.State;
import cpp.RawPointer;
import cpp.Callable;

class MetatableFunctions {

    public static final callIndex           = Callable.fromStaticFunction(_callIndex);
    public static final callNewIndex        = Callable.fromStaticFunction(_callNewIndex);
    public static final callMetatableCall   = Callable.fromStaticFunction(_callMetatableCall);
    public static final callGarbageCollect  = Callable.fromStaticFunction(_callGarbageCollect);
    public static final callEnumIndex       = Callable.fromStaticFunction(_callEnumIndex);
    public static final callGlobalIndex     = Callable.fromStaticFunction(_callGlobalIndex);
    public static final callGlobalNewIndex  = Callable.fromStaticFunction(_callGlobalNewIndex);

    static function _callIndex(state:StatePointer):Int          { return metatableFunc(LScript.currentLua.luaState, 0); }
    static function _callNewIndex(state:StatePointer):Int       { return metatableFunc(LScript.currentLua.luaState, 1); }
    static function _callMetatableCall(state:StatePointer):Int  { return metatableFunc(LScript.currentLua.luaState, 2); }
    static function _callGarbageCollect(state:StatePointer):Int { return metatableFunc(LScript.currentLua.luaState, 3); }
    static function _callEnumIndex(state:StatePointer):Int      { return metatableFunc(LScript.currentLua.luaState, 4); }
    static function _callGlobalIndex(state:StatePointer):Int    { return globalMetatableFunc(LScript.currentLua.luaState, 0); }
    static function _callGlobalNewIndex(state:StatePointer):Int { return globalMetatableFunc(LScript.currentLua.luaState, 1); }


    static function metatableFunc(state:State, funcNum:Int):Int {
        var indexWrapper           = function(obj:Dynamic, key:Dynamic, _:Dynamic):Dynamic return index(obj, key);
        var newIndexWrapper        = function(obj:Dynamic, key:Dynamic, val:Dynamic):Dynamic return newIndex(obj, key, val);
        var callWrapper            = function(func:Dynamic, obj:Dynamic, args:Dynamic):Dynamic return metatableCall(func, obj, args);
        var gcWrapper              = function(idx:Dynamic, _:Dynamic, __:Dynamic):Dynamic { garbageCollect(idx); return null; };
        var enumWrapper            = function(e:Dynamic, name:Dynamic, args:Dynamic):Dynamic return enumIndex(e, name, args);
    
        final functions:Array<Dynamic->Dynamic->Dynamic->Dynamic> = [
            indexWrapper, newIndexWrapper, callWrapper, gcWrapper, enumWrapper
        ];
    
        final nparams = Lua.gettop(state);
    
        var specialIndex:Int = -1;   
        var parentIndex:Int  = -1;
        var dummySpecial:Int = -1;
        var dummyParent:Int = -1;
    
        final params = [];
        for (i in 0...nparams) {
            if (i == 0) {
                params.push(CustomConvert.fromLua(-nparams + i,
                                                  RawPointer.addressOf(specialIndex),
                                                  RawPointer.addressOf(parentIndex),
                                                  true));
            } else {
                params.push(CustomConvert.fromLua(-nparams + i,
                                                  RawPointer.addressOf(dummySpecial),
                                                  RawPointer.addressOf(dummyParent),
                                                  false));
            }
        }
    
        if (funcNum == 2) {
            final objParent = (parentIndex >= 0) ? LScript.currentLua.specialVars[parentIndex] : null;
            if (params[1] != objParent) params.insert(1, objParent);
        
            params.push(cast params.splice(2, params.length - 2));         
        }
    
        var returned:Dynamic = null;
        try {
            returned = functions[funcNum](params[0], params[1], params[2]);
        } catch (e:Dynamic) {
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

/* ----------------------------------------------------
 *  global 表的 __index / __newindex
 * --------------------------------------------------- */
    static function globalMetatableFunc(state:State, funcNum:Int):Int {
        if (state == null) return 0;

        final functions = [globalIndex, globalNewIndex];

        var returned:Dynamic = null;
        try {
            final nparams = Lua.gettop(state);
            if (nparams < 2) {
                Lua.settop(state, 0);
                return 0;
            }

            /* 同样：先建变量再取地址 */
            var dummy:Int = -1;
            final params = [];
            for (i in 0...nparams) {
                params.push(CustomConvert.fromLua(-nparams + i, RawPointer.addressOf(dummy)));
            }

            if (LScript.currentLua != null && LScript.GlobalVars != null)
                returned = functions[funcNum](params[1], params[2]);
        } catch (e:Dynamic) {
            try { LuaL.error(state, "Global Variable Error: " + e.details()); } catch (_) {}
            Lua.settop(state, 0);
            return 0;
        }

        Lua.settop(state, 0);
        if (returned != null) {
            try { CustomConvert.toLua(returned); return 1; } catch (_) {}
        }
        return 0;
    }

    public static function index(object:Dynamic, property:Any, ?_:Any):Dynamic {
        if (object is Array && property is Int) return object[cast property];
        final prop = cast property, String;
        return (object != null) ? Reflect.getProperty(object, prop) : null;
    }

    public static function newIndex(object:Dynamic, property:Any, value:Dynamic):Dynamic {
        if (object is Array && property is Int) {
            object[cast property] = value;
            return null;
        }
        final prop = cast property, String;
        if (object == null) return null;
        try Reflect.setProperty(object, prop, value)
        catch (_) try object.setProperty(prop, value)
        catch (_) try Reflect.setField(object, prop, value) catch (_) {}
        return null;
    }

    public static function metatableCall(func:Dynamic, object:Dynamic, ?params:Array<Any>):Dynamic
        return (func != null && Reflect.isFunction(func)) ? Reflect.callMethod(object, func, params != null ? params : []) : null;

    public static function garbageCollect(index:Int):Void {
        LScript.currentLua.avalibableIndexes.push(index);
        LScript.currentLua.specialVars.remove(index);
    }

    public static function enumIndex(object:Enum<Dynamic>, value:String, ?params:Array<Any>):EnumValue
        return (object != null) ? object.createByName(value, params != null ? params : []) : null;

    public static function globalIndex(property:String, ?_:Any):Dynamic
        return (property != null && LScript.GlobalVars != null && LScript.GlobalVars.exists(property)) ? LScript.GlobalVars.get(property) : null;

    public static function globalNewIndex(property:String, value:Dynamic):Dynamic {
        if (property != null && LScript.GlobalVars != null) LScript.GlobalVars.set(property, value);
        return null;
    }
}




