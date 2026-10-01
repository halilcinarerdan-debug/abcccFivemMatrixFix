#include "script_component.hpp"
/*
 * Author: nkenny
 * moved the unit into cover
 *
 * Arguments:
 * 0: unit doing the flight <OBJECT>
 * 1: position of cover <ARRAY>
 *
 * Return Value:
 * bool
 *
 * Example:
 * [bob] call lambs_main_fnc_doCover;
 *
 * Public: No
*/

params ["_unit", ["_pos", [], [[]]], ["_enemy", objNull, [objNull, []]]];

// stance change (one step lower)
_unit setUnitPosWeak (["DOWN", "MIDDLE"] select ((stance _unit) isEqualTo "STAND"));

// check if stopped or inside a building
if (!(_unit checkAIFeature "PATH") || {(insideBuilding _unit) isEqualTo 1}) exitWith {false};

// 2026-10-01 FIX: dusman bilinmeden "siper" secilirdi (agacin hangi tarafinda oldugu
// dusmanla ilgisizdi, BUSH da siper sayiliyordu). Artik dusman varsa findCover'dan
// gercek (dusmana gore golgede kalan) pozisyon alinir.
private _dusman = if (_enemy isEqualType objNull) then {
    if (isNull _enemy) then {_unit findNearestEnemy _unit} else {_enemy}
} else {
    _enemy
};
private _dusmanVar = (_dusman isEqualType []) || {!isNull _dusman};

// find cover
if (_pos isEqualTo []) then {
    if (_dusmanVar) then {
        // 2 sn onbellek: FSM her tick'te cagirir, her seferinde tarama yapma
        private _onbellek = _unit getVariable [QGVAR(coverCache), [-10, []]];
        if ((time - (_onbellek select 0)) < ELITE_COVER_CACHE_TIME && {(_onbellek select 1) isNotEqualTo []}) then {
            _pos = _onbellek select 1;
        } else {
            private _cover = [_unit, _dusman, 25, "ASCEND", 1] call FUNC(findCover);
            if (_cover isNotEqualTo []) then {
                _pos = (_cover select 0) select 0;
                _unit setUnitPosWeak ((_cover select 0) select 1);
                _unit setVariable [QGVAR(coverCache), [time, _pos]];
            };
        };
    };
};

// yedek: yakin agac / HIDE objesi (BUSH cikarildi - mermi durdurmaz)
if (_pos isEqualTo []) then {
    private _objeler = nearestTerrainObjects [_unit, ["TREE", "HIDE"], 6, true, true];
    _pos = if (_objeler isEqualTo []) then {
        getPosASL _unit
    } else {
        private _obj = _objeler select 0;
        if (_dusmanVar) then {
            // dusmana gore objenin ARKASI
            _obj getPos [1.2, (_dusman call CBA_fnc_getPos) getDir _obj]
        } else {
            _obj getPos [-1.2, _unit getDir _obj]
        }
    };
};

// force anim
if (_unit distance2D _pos < 0.6) exitWith {false};
private _direction = _unit getRelDir _pos;
private _anim = call {
    if (_direction > 315) exitWith {["WalkF", "WalkLF"]};
    if (_direction > 225) exitWith {["WalkL", "WalkLF"]};
    if (_direction > 135) exitWith {["WalkB"]};
    if (_direction > 45) exitWith {["WalkR", "WalkRF"]};
    ["WalkF", "WalkRF"]
};

// prevent run in place
_unit moveTo _pos;
_unit setDestination [_pos, "FORMATION PLANNED", true];

// do anim
[_unit, _anim, false] call FUNC(doGesture);       // gesture is not forced to allow cover movement to appear smoother - nkenny

// end
true
