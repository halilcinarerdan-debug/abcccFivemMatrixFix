#include "script_component.hpp"
/*
 * Author: Cinar (ELITE fork)
 * Raycast tabanli elit cover secimi
 * 2026-10-01 v3 - Bot sayisina gore dinamik kalite
 *   < 10 bot  -> FULL (16 yon, 4 mesafe, 64 raycast)
 *   < 30 bot  -> NORMAL (8 yon, 3 mesafe, 24 raycast)
 *   < 60 bot  -> HAFIF (8 yon, 2 mesafe, 16 raycast)
 *   < 150 bot -> LITE (4 yon, 2 mesafe, 8 raycast)
 *   150+ bot  -> ULTRA-LITE (4 yon, 1 mesafe, 4 raycast)
*/

params [
    ["_unit", objNull, [objNull]],
    ["_enemy", [0,0,0], [[], objNull]],
    ["_forceMove", false, [false]]
];

if (isNull _unit || {!alive _unit}) exitWith {[]};
if (_enemy isEqualTo [] || {_enemy isEqualTo [0,0,0]}) exitWith {[]};

// BOT SAYISI - 15 sn cache (her cagride allUnits saymamak icin)
// 2026-10-01 FIX: tanimsiz global okuma hatasi (nil) onlendi
private _botSayisi = missionNamespace getVariable [QGVAR(eliteCoverBotCache), -1];
if (_botSayisi < 0) then {
    _botSayisi = count allUnits;
    GVAR(eliteCoverBotCache) = _botSayisi;
    [{
        GVAR(eliteCoverBotCache) = nil;
    }, [], 15] call CBA_fnc_waitAndExecute;
};

// THROTTLE - bot sayisina gore otomatik
private _throttle = switch (true) do {
    case (_botSayisi < 10):  { 0.02 };
    case (_botSayisi < 30):  { 0.03 };
    case (_botSayisi < 60):  { 0.05 };
    case (_botSayisi < 150): { 0.08 };
    default                  { 0.10 };
};
private _sonCagri = missionNamespace getVariable [QGVAR(eliteCoverLastCall), 0];
if (time - _sonCagri < _throttle) exitWith {[]};
GVAR(eliteCoverLastCall) = time;

// Enemy normalize
private _enemyPos = if (_enemy isEqualType objNull) then {
    if (isNull _enemy) exitWith {[0,0,0]};
    getPosATL _enemy
} else {
    _enemy
};
if (_enemyPos isEqualTo [0,0,0]) exitWith {[]};

private _unitPos = getPosATL _unit;
if ((_unitPos select 2) > 50) exitWith {[]};

// KALITE - bot sayisina gore otomatik
private _yonMax = switch (true) do {
    case (_botSayisi < 10):  { 15 };
    case (_botSayisi < 60):  { 7 };
    default                  { 3 };
};
private _mesafeMax = switch (true) do {
    case (_botSayisi < 10):  { 4 };
    case (_botSayisi < 30):  { 3 };
    case (_botSayisi < 60):  { 2 };
    case (_botSayisi < 150): { 2 };
    default                  { 1 };
};
private _mesafeAdim = if (_botSayisi < 10) then { 4 } else { 6 };
private _yonAdim = 360 / (_yonMax + 1);

private _unitYer = getTerrainHeightASL _unitPos;
private _enemyGozASL = AGLToASL (_enemyPos vectorAdd [0, 0, 1.2]);
private _bakisYonu = _unitPos getDir _enemyPos;

private _adaylar = [];

for "_i" from 0 to _yonMax do {
    private _yon = _i * _yonAdim;
    for "_m" from 1 to _mesafeMax do {
        private _mesafe = _m * _mesafeAdim;
        private _adayPos = _unitPos getPos [_mesafe, _yon];

        if (!surfaceIsWater _adayPos) then {
            private _adayYer = getTerrainHeightASL _adayPos;
            if ((abs (_adayYer - _unitYer)) <= 3) then {
                _adayPos set [2, (_unitPos select 2)];

                private _adayGozASL = AGLToASL (_adayPos vectorAdd [0, 0, 1.2]);
                // 2026-10-01 FIX: eskiden dusmana giden hatta HERHANGI bir sey (dusmanin
                // 5m onundeki agac bile) "siper" sayiliyordu. Simdi:
                //  1) adayin hemen onunde (4m) gercek bir engel olmali
                //  2) tam hat da kapali olmali
                private _yonVek = vectorNormalized (_enemyGozASL vectorDiff _adayGozASL);
                private _engelVar = lineIntersects [_adayGozASL, _adayGozASL vectorAdd (_yonVek vectorMultiply 4), _unit, objNull];
                if (_engelVar) then {
                    _engelVar = lineIntersects [_adayGozASL, _enemyGozASL, _unit, objNull];
                };

                if (_engelVar) then {
                    private _adayBakisYonu = _adayPos getDir _enemyPos;
                    private _aciFarki = abs (_bakisYonu - _adayBakisYonu);
                    if (_aciFarki > 180) then { _aciFarki = 360 - _aciFarki; };

                    private _puan = 100;
                    _puan = _puan + ((_mesafeMax - _m + 1) * 15);
                    _puan = _puan + ((180 - _aciFarki) * 0.15);

                    // dusmana YAKLASAN adaylari cezalandir (siper arayan ileri kosmasin)
                    private _yaklasma = (_unitPos distance2D _enemyPos) - (_adayPos distance2D _enemyPos);
                    if (_yaklasma > 0) then { _puan = _puan - (_yaklasma * 3); };

                    _adaylar pushBack [_puan, _adayPos, _mesafe, _aciFarki];
                };
            };
        };
    };
};

if (_adaylar isEqualTo []) exitWith {[]};

_adaylar sort false;
private _enIyi = _adaylar select 0;
private _coverPos = _enIyi select 1;

if (_forceMove) then {
    _unit doMove _coverPos;
    _unit setUnitPosWeak "MIDDLE";
};

if (EGVAR(main,debug_functions)) then {
    private _mod = switch (true) do {
        case (_botSayisi < 10):  { "FULL" };
        case (_botSayisi < 30):  { "NORMAL" };
        case (_botSayisi < 60):  { "HAFIF" };
        case (_botSayisi < 150): { "LITE" };
        default                  { "ULTRA-LITE" };
    };
    diag_log format [
        "[ELIT-COVER] %1 | bot:%2 %3 | aday:%4 | puan:%5 | mesafe:%6m",
        name _unit,
        _botSayisi,
        _mod,
        count _adaylar,
        round (_enIyi select 0),
        round (_enIyi select 2)
    ];
};

_coverPos