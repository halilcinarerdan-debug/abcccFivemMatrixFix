#include "script_component.hpp"
/*
 * Author: diwako
 * Returns position and stance of closest possible cover location.
 *
 * Arguments:
 * 0: Unit seeking cover <OBJECT>
 * 1: Enemy <OBJECT> or Enemy Position (AGL) <ARRAY>
 * 2: Range to find cover, default 15 <NUMBER>
 * 3: Sort mode <STRING>, default "ASCEND", possible values: ASCEND, DESCEND, RANDOM. ASCEND returns closest possible location
 * 4: Max Results <Number>, default 1, Maximum amount of results that can be returned, -1 for all (warning may be slow)
 *
 * Return Value:
 * Array of format [_posAGL, _stance], when no cover found then an empty array is returned
 * Stance can be "UP", "MIDDLE" or "DOWN"
 *
 * Example:
 * [bob, angryJoe, 50] call lambs_main_fnc_findCover
 *
 * Public: Yes
*/
params [
    ["_unit", objNull, [objNull]],
    ["_enemy", objNull, [objNull, []]],
    ["_range", ELITE_COVER_RANGE],
    ["_sortMode", "ASCEND", [""]],
    ["_maxResults", ELITE_COVER_MAX_RESULTS]
];

_maxResults = floor _maxResults;
private _ret = [];

if (_maxResults isEqualTo 0) exitWith {_ret};

private _dangerPos = (_enemy call CBA_fnc_getPos) vectorAdd [0, 0, 1.8];

if (_dangerPos isNotEqualTo [0, 0, 1.8]) then {
    private _enemyPos = _enemy call CBA_fnc_getPos;
    _dangerPos = AGLToASL _dangerPos;
    private _terrainObjects = nearestTerrainObjects [_unit, ["BUSH", "TREE", "SMALL TREE", "HIDE", "BUILDING"], _range, false, true];
    // 2026-10-01 FIX: murettebatli (hareketli / dost) arac siper sayilmaz,
    // "building" zaten terrainObjects icinde -> ciftleme yok
    private _vehicles = (nearestObjects [_unit, ["building", "Car"], _range]) select {
        !(_x in _terrainObjects)
        && {((crew _x) findIf {alive _x}) isEqualTo -1}
    };

    private _allObjs = [];
    if(_sortMode in ["ASCEND", "DESCEND"]) then {
        _allObjs = [_terrainObjects + _vehicles, [], {_unit distance2D _x}, _sortMode] call BIS_fnc_sortBy;
    } else {
        _allObjs = (_terrainObjects + _vehicles) call BIS_fnc_arrayShuffle;
    };

    private _found = false;
    private _numFound = 0;
    private _obj = objNull;
    private _pos = [];
    private _posASL = [];
    private _buildingPos = [];

    while {!_found && {_allObjs isNotEqualTo []}} do {
        _obj = _allObjs deleteAt 0;
        _buildingPos = [_obj, ELITE_COVER_BUILDING_POS] call CBA_fnc_buildingPositions;
        if (_buildingPos isEqualTo []) then {
            // 2026-10-01 FIX: eskiden bounding box KOSESI (donmemis, rastgele) seciliyordu ->
            // pozisyon cogu zaman objenin yan/on tarafinda, dusmana acik kaliyordu.
            // Simdi: dusmana gore objenin ARKA tarafi, bbox disina +0.8m.
            private _objPos = getPosATL _obj;
            private _awayDir = _enemyPos getDir _objPos;
            private _farPos = _objPos getPos [50, _awayDir];
            private _loc = _obj worldToModel _farPos;
            private _dx = _loc select 0;
            private _dy = _loc select 1;
            private _len = (sqrt ((_dx * _dx) + (_dy * _dy))) max 0.001;
            _dx = _dx / _len;
            _dy = _dy / _len;
            (boundingBoxReal _obj) params ["_bbMin", "_bbMax"];
            private _ex = if (_dx >= 0) then {_bbMax select 0} else {abs (_bbMin select 0)};
            private _ey = if (_dy >= 0) then {_bbMax select 1} else {abs (_bbMin select 1)};
            private _t = 15;
            if ((abs _dx) > 0.01) then {_t = _t min (_ex / (abs _dx));};
            if ((abs _dy) > 0.01) then {_t = _t min (_ey / (abs _dy));};
            _pos = _objPos getPos [_t + 0.8, _awayDir];
            // yukseklik 0.1 (yoksa pozisyon objenin tam ustunde olur)
            _pos set [2, 0.1];
            _buildingPos = [_pos];
        };

        {
            if (_found) exitWith {};
            if ((_dangerPos distance2D _x) > ELITE_COVER_MIN_DIST) then {
                _pos = _x;
                _posASL = AGLToASL _x;

                // check down position
                if (lineIntersects [_dangerPos, _posASL vectorAdd [0, 0, 0.1], _unit]) exitWith {
                    private _stances = ["DOWN"];
                    // check middle position
                   if (lineIntersects [_dangerPos, _posASL vectorAdd [0, 0, 0.75], _unit]) then {
    _stances pushBack "MIDDLE";
    if (lineIntersects [_dangerPos, _posASL vectorAdd [0, 0, 1.45], _unit]) then {
        _stances pushBack "UP";
    };
};
                    // Gizlenmis stance'larin EN YUKSEGI (hepsi korunakli; rastgele yatma yok)
                    _ret pushBack [_pos, _stances select ((count _stances) - 1)];
                    _numFound = _numFound + 1;

                    _found = ((_maxResults isNotEqualTo -1) && {_numFound isEqualTo _maxResults});
                };
            };
        } forEach _buildingPos
    };
};

if (GVAR(debug_functions) && {(_ret isNotEqualTo [])}) then {
    ["Found %1 cover positions", count _ret] call FUNC(debugLog);
    {
        "Sign_Arrow_Large_F" createVehicleLocal ((_enemy call CBA_fnc_getPos) vectorAdd [0, 0, 1.8]);
        private _add = if ((_x select 1) isEqualTo "UP") then {
            2
        } else {
            [0.2, 1] select (_x select 1 isEqualTo "MIDDLE");
        };
        "Sign_Arrow_Large_Blue_F" createVehicleLocal ((_x select 0) vectorAdd [0, 0, _add]);
    } forEach _ret;
};

_ret
