#include "script_component.hpp"
/*
 * Author: Cinar (ELITE fork)
 * Kademeli Geri Cekilme - NATO/USMC piyade doktrini
 * 2026-10-01 FIX v12
 *   - moveTo (LAMBS FSM ezemez), varana kadar 4 sn'de bir tazelenir
 *   - Takimlar splitFireTeams'ten (FSE gercekten FSE: son cikar, o zamana kadar ates eder)
 *   - Cekilme sonrasi 45 sn cooldown (arka arkaya cekilme dongusu yok)
 *   - Guvenlik valfi sadece KENDI cekilmesini temizler
 *   - Orijinal combatMode saklanir/geri yuklenir (eskiden BLUE -> YELLOW zorlaniyordu)
 *   - Rally noktalari suya dusmez
 *   - Skill SABIT (sadece animasyon hizi degisir)
*/

params [
    ["_group", grpNull, [grpNull, objNull]],
    ["_target", objNull, [objNull, []]]
];

if (_group isEqualType objNull) then {_group = group _group;};
if (isNull _group) exitWith {false};
if ((units _group) isEqualTo []) exitWith {false};

private _unit = leader _group;
if (isNull _unit) exitWith {false};

if (_group getVariable [QGVAR(isRetreating), false]) exitWith {false};

private _targetPos = _target call CBA_fnc_getPos;
if ((_targetPos select 2) > 6) then { _targetPos set [2, 0.5]; };

// ---------------------------------------------------------------------------
// COOLDOWN — cekilme biteli 45 sn dolmadiysa tekrar kacma, pozisyon tut
// ---------------------------------------------------------------------------
private _sonBitis = _group getVariable [QGVAR(retreatEndTime), -999];
if ((time - _sonBitis) < 45) exitWith {
    _group setVariable [QGVAR(isExecutingTactic), true];
    [_group, _target] call FUNC(tacticsHold);
    [{
        params ["_g"];
        if (!isNull _g) then {
            _g setVariable [QGVAR(isExecutingTactic), nil];
        };
    }, [_group], 20] call CBA_fnc_waitAndExecute;
    false
};

// ---------------------------------------------------------------------------
// CQB-IPTAL — 40m altinda + meskun mahal: kacmak olu demek, tut
// ---------------------------------------------------------------------------
private _cqbMesafe = _unit distance2D _targetPos;
private _cqbBinalar = nearestTerrainObjects [
    getPosATL _unit,
    ["BUILDING", "HOUSE", "CHURCH", "FUELSTATION"],
    30, false, true
];
private _cqbUrban = (count _cqbBinalar) >= 3;

if (_cqbMesafe < 40 && _cqbUrban) exitWith {
    _group setVariable [QGVAR(isExecutingTactic), true];
    [_group, _target] call FUNC(tacticsHold);
    [{
        params ["_g"];
        if (!isNull _g) then {
            _g setVariable [QGVAR(isExecutingTactic), nil];
        };
    }, [_group], 20] call CBA_fnc_waitAndExecute;
    false
};

// ---------------------------------------------------------------------------
// RALLY NOKTALARI — dusmandan uzaga, suya dusmesin
// ---------------------------------------------------------------------------
private _leaderPos = getPosATL _unit;
private _threatDir = [_targetPos, _leaderPos] call BIS_fnc_dirTo;

private _suKontrol = {
    params ["_p", "_o"];
    private _i = 0;
    while {surfaceIsWater _p && {_i < 6}} do {
        _p = _o getPos [((_p distance2D _o) * 0.7), (_o getDir _p)];
        _i = _i + 1;
    };
    _p
};

private _rallyAna   = [_leaderPos getPos [120, _threatDir], _leaderPos] call _suKontrol;
private _rallyAlt   = [_rallyAna getPos [80, _threatDir + 45], _leaderPos] call _suKontrol;
private _rallyNihai = [_leaderPos getPos [250, _threatDir], _leaderPos] call _suKontrol;

private _baslangic = time;
_group setVariable [QGVAR(isRetreating), true];
_group setVariable [QGVAR(isExecutingTactic), true];
_group setVariable [QGVAR(retreatStartTime), _baslangic];
_group setVariable [QGVAR(rallyIndex), 0];

// ---------------------------------------------------------------------------
// GUVENLIK VALFI — sadece bu cekilmenin bayraklarini temizler
// ---------------------------------------------------------------------------
[_group, _baslangic, time + 130] spawn {
    params ["_g", "_start", "_limit"];
    waitUntil { time > _limit || {isNull _g} };
    if (!isNull _g && {((_g getVariable [QGVAR(retreatStartTime), -1]) isEqualTo _start)}) then {
        if (_g getVariable [QGVAR(isRetreating), false]) then {
            _g setVariable [QGVAR(isRetreating), nil];
            _g setVariable [QGVAR(isExecutingTactic), nil];
            _g setVariable [QGVAR(retreatEndTime), time];
            _g setSpeedMode "NORMAL";
            _g enableAttack true;
            {
                if (alive _x) then {
                    _x enableAI "TARGET";
                    _x enableAI "AUTOTARGET";
                    _x allowFleeing 0;
                    _x setAnimSpeedCoef 1.0;
                };
            } forEach (units _g);
        };
    };
};

if (EGVAR(main,debug_functions)) then {
    private _msg = format [
        "[GERI-CEKILME-BASLA] %1 | tehdit:%2m | ANA:%3 ALT:%4 NIHAI:%5",
        groupId _group, round (_unit distance2D _targetPos),
        _rallyAna, _rallyAlt, _rallyNihai
    ];
    systemChat _msg;
    diag_log _msg;
};

[_group, _unit, _targetPos, _rallyAna, _baslangic] spawn {
    params ["_group", "_unit", "_targetPos", "_rallyAna", "_baslangic"];

    private _origCombat = combatMode _group;

    _group setFormation "FILE";
    _group setFormDir (_unit getDir _targetPos);
    _group setSpeedMode "FULL";
    _group enableAttack false;

    private _tumBirimler = (units _group) select {alive _x && {isNull objectParent _x}};

    // 3 TAKIM — splitFireTeams ile ayni mantik
    private _takimlar = [_group] call FUNC(splitFireTeams);
    _takimlar params ["_fse", "_maneuver", "_reserve"];

    // Yedek: splitFireTeams bos dondururse (4 kisiden az) 3'e bol
    if (_fse isEqualTo [] || {_maneuver isEqualTo []}) then {
        _fse = [];
        _maneuver = [];
        _reserve = [];
        {
            private _m = _forEachIndex % 3;
            if (_m isEqualTo 0) then {
                _reserve pushBack _x;
            } else {
                if (_m isEqualTo 1) then {
                    _maneuver pushBack _x;
                } else {
                    _fse pushBack _x;
                };
            };
        } forEach _tumBirimler;
    };

    // FSM SUSTUR + ANIMASYON HIZLANDIR (skill SABIT kalir)
    // FSE son cikar: o zamana kadar hedef alip ates etmeye devam eder.
    {
        _x disableAI "TARGET";
        _x disableAI "AUTOTARGET";
    } forEach (_reserve + _maneuver);

    {
        _x setBehaviour "AWARE";
        _x allowFleeing 1;
        _x setAnimSpeedCoef 1.15;
    } forEach _tumBirimler;

    if (EGVAR(main,debug_functions)) then {
        diag_log format [
            "[GERI-CEKILME] %1 takimlar | FSE:%2 MVR:%3 RES:%4",
            groupId _group, count _fse, count _maneuver, count _reserve
        ];
    };

    // Takimi hedefe kadar (en fazla _azamiSure sn) 4 sn'de bir moveTo ile surer
    private _hareket = {
        params ["_grup", "_birimler", "_pos", "_azamiSure"];
        private _bitis = time + _azamiSure;
        while {time < _bitis && {!isNull _grup}} do {
            private _gelmeyen = _birimler select {
                alive _x && {isNull objectParent _x} && {(_x distance2D _pos) > 8}
            };
            if (_gelmeyen isEqualTo []) exitWith {};
            { _x moveTo _pos; } forEach _gelmeyen;
            sleep 4;
        };
    };

    // FAZ 1 - RESERVE
    if (EGVAR(main,debug_functions)) then {
        diag_log format ["[GERI-CEKILME] FAZ 1: RESERVE -> ANA (%1 kisi)", count _reserve];
    };
    [_group, _reserve, _rallyAna, 25] call _hareket;

    // FAZ 2 - MANEUVER
    if (EGVAR(main,debug_functions)) then {
        diag_log format ["[GERI-CEKILME] FAZ 2: MANEUVER -> ANA (%1 kisi)", count _maneuver];
    };
    [_group, _maneuver, _rallyAna, 25] call _hareket;

    // FAZ 3 - FSE (en son, kosarken ates etmez)
    if (EGVAR(main,debug_functions)) then {
        diag_log format ["[GERI-CEKILME] FAZ 3: FSE -> ANA (%1 kisi)", count _fse];
    };
    {
        _x disableAI "TARGET";
        _x disableAI "AUTOTARGET";
    } forEach _fse;
    [_group, _fse, _rallyAna, 30] call _hareket;

    // TEMIZLIK
    if (!isNull _group && {((_group getVariable [QGVAR(retreatStartTime), -1]) isEqualTo _baslangic)}) then {
        _group setVariable [QGVAR(isRetreating), nil];
        _group setVariable [QGVAR(isExecutingTactic), nil];
        _group setVariable [QGVAR(retreatEndTime), time];
        _group setSpeedMode "NORMAL";
        _group enableAttack true;
        _group setCombatMode _origCombat;

        {
            if (alive _x) then {
                _x enableAI "TARGET";
                _x enableAI "AUTOTARGET";
                _x setBehaviour "AWARE";
                _x allowFleeing 0;
                _x setAnimSpeedCoef 1.0;
                _x setUnitPos "AUTO";
                _x doFollow (leader _x);
            };
        } forEach (units _group);

        if (EGVAR(main,debug_functions)) then {
            diag_log format ["[GERI-CEKILME-TAMAM] %1", groupId _group];
        };
    };
};

true
