#include "script_component.hpp"
/*
 * Author: Cinar (ELITE fork)
 * Grubu 3 fire team'e boler: Fire Support / Maneuver / Reserve
 * NATO doktrini + dinamik boyut (grup sayisina gore)
 *
 * Arguments:
 * 0: group <GROUP> or leader <OBJECT>
 *
 * Return Value:
 * [FSE <ARRAY>, Maneuver <ARRAY>, Reserve <ARRAY>]
 *
 * Public: No
*/

params [["_group", grpNull, [grpNull, objNull]]];
if (_group isEqualType objNull) then {_group = group _group;};
if (isNull _group) exitWith {[[], [], []]};

private _units = (units _group) select {alive _x && {isNull objectParent _x}};
private _count = count _units;
if (_count < 4) exitWith {[_units, [], []]};

// ---------------------------------------------------------------------------
// DINAMIK BOYUT TABLOSU (NATO doktrini)
// ---------------------------------------------------------------------------
private _fseSize = 0;
private _mvrSize = 0;

switch (true) do {
    case (_count >= 12): { _fseSize = 4; _mvrSize = 4; };
    case (_count >= 9):  { _fseSize = 3; _mvrSize = 3; };
    case (_count >= 7):  { _fseSize = 3; _mvrSize = 4; };
    case (_count >= 5):  { _fseSize = 2; _mvrSize = 3; };
    default              { _fseSize = 2; _mvrSize = 2; };
};

// ---------------------------------------------------------------------------
// KATEGORIZE — MG/AT/sniper = heavy, digerleri = normal
// ---------------------------------------------------------------------------
private _leader = leader _group;
private _heavies = [];
private _normals = [];

{
    if (_x isEqualTo _leader) then {
        _normals pushBack _x;
    } else {
        private _wpn = primaryWeapon _x;
        private _wpnType = getNumber (configFile >> "CfgWeapons" >> _wpn >> "type");
        private _hasLauncher = (secondaryWeapon _x) isNotEqualTo "";
        if (_wpnType in [4, 5] || _hasLauncher) then {
            _heavies pushBack _x;
        } else {
            _normals pushBack _x;
        };
    };
} forEach _units;

// ---------------------------------------------------------------------------
// DAGITIM
// ---------------------------------------------------------------------------
private _fse = [];
private _maneuver = [];
private _reserve = [];

// 1) Lider maneuver'a
if (_leader in _normals) then {
    _maneuver pushBack _leader;
    _normals deleteAt (_normals find _leader);
};

// 2) FSE = heavy'ler (max _fseSize)
while {count _fse < _fseSize && count _heavies > 0} do {
    _fse pushBack (_heavies deleteAt 0);
};

// 3) Maneuver = kalan rifleman
while {count _maneuver < _mvrSize && count _normals > 0} do {
    _maneuver pushBack (_normals deleteAt 0);
};

// 3b) FSE hala eksikse (agir silahli yoksa) normal askerlerle tamamla
while {count _fse < _fseSize && count _normals > 0} do {
    _fse pushBack (_normals deleteAt ((count _normals) - 1));
};

// 4) Reserve = artan
_reserve = _heavies + _normals;

// 5) Guvenlik: FSE veya Maneuver bos ise reserve'den ekle
if (_fse isEqualTo [] && {count _reserve > 0}) then {
    _fse pushBack (_reserve deleteAt 0);
};
if (count _maneuver < 2 && {count _reserve > 0}) then {
    _maneuver pushBack (_reserve deleteAt 0);
};

// Debug
if (EGVAR(main,debug_functions)) then {
    diag_log format [
        "[FIRETEAM] %1 (%2 kisi) -> FSE:%3 MVR:%4 RES:%5",
        groupId _group, _count, count _fse, count _maneuver, count _reserve
    ];
};

[_fse, _maneuver, _reserve]