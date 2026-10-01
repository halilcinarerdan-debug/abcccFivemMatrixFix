#include "script_component.hpp"
/*
 * Author: Cinar (ELITE fork)
 * Grup, USMC doktrinine uygun "Bounding Overwatch" manevrasi yapar.
 * 2026-10-01 FIX v2 - Overwatch agresif + hizli cycle
*/

params ["_group", "_target", ["_units", []], ["_delay", 180]];

// ---------------------------------------------------------------------------
// Lokal bounding sabitleri (USMC doktrini)
// ---------------------------------------------------------------------------
private _BND_ASSAULT_RANGE   = 55;
private _BND_CYCLE_BASE      = 5;
private _BND_CYCLE_RAND      = 3;
private _BND_SUPPRESSION_MUL = 3;
private _BND_MAX_CYCLES      = 12;
private _BND_COVER_RANGE     = 15;

// ---------------------------------------------------------------------------
// Grup / lider dogrulama
// ---------------------------------------------------------------------------
if (isNull _group) exitWith {false};
if (_group isEqualType objNull) then {_group = group _group;};
if ((units _group) isEqualTo []) exitWith {false};
private _unit = leader _group;

// ---------------------------------------------------------------------------
// Hedefi normalize et
// ---------------------------------------------------------------------------
_target = _target call CBA_fnc_getPos;
if ((_target select 2) > 6) then {
    _target set [2, 0.5];
};

private _targetASL = AGLToASL _target;

// ---------------------------------------------------------------------------
// CQB ise assault'a devret
// ---------------------------------------------------------------------------
private _boundingCQB = (GVAR(cqbRange) min 20);
if (_unit distance2D _target < _boundingCQB) exitWith {
    [_group, _target] call FUNC(tacticsAssault);
    false
};

// ---------------------------------------------------------------------------
// Minimum 4 kisi
// ---------------------------------------------------------------------------
if (count (units _group) < 4) exitWith {
    [_group, _target] call FUNC(tacticsFlank);
    false
};

// ---------------------------------------------------------------------------
// Taktik kilidi + bounding bayragi
// ---------------------------------------------------------------------------
_group setVariable [QGVAR(isExecutingTactic), true];
_group setVariable [QGVAR(isBounding), true];
_group setVariable [QGVAR(boundingStartTime), time];
private _bndToken = format ["%1-%2", time, random 1000000];
_group setVariable [QGVAR(bndToken), _bndToken];

// ---------------------------------------------------------------------------
// Cleanup timer
// ---------------------------------------------------------------------------
[
    {
        params [["_group", grpNull], ["_delay", 0], "", "", ["_token", ""]];
        time > _delay
        || {isNull _group}
        || { !(_group getVariable [QGVAR(isExecutingTactic), false]) }
        || { (_group getVariable [QGVAR(bndToken), ""]) isNotEqualTo _token }
    },
    {
        params [["_group", grpNull], "", ["_speedMode", "NORMAL"], ["_formation", "WEDGE"], ["_token", ""]];
        // Token eslesmiyorsa baska bir taktik (Retreat / yeni Bounding) devraldi -> dokunma
        if (!isNull _group && {(_group getVariable [QGVAR(bndToken), ""]) isEqualTo _token}) then {
            _group setVariable [QGVAR(bndToken), nil];
            _group enableAttack true;
            (units _group) allowGetIn true;
            _group setVariable [QGVAR(isExecutingTactic), nil];
            _group setVariable [QGVAR(isBounding), nil];
            _group setVariable [QEGVAR(main,currentTactic), nil];
            _group setSpeedMode _speedMode;

            private _u2 = leader _group;
            private _t2 = _u2 getVariable [QEGVAR(main,currentTarget), [0,0,0]];
            _t2 = _t2 call CBA_fnc_getPos;
            if (_t2 isEqualTo [0,0,0]) then { _t2 = getPosATL _u2 vectorAdd [50, 0, 0]; };
            private _yeniForm = [_u2, _t2, "BOUNDING"] call FUNC(selectFormation);
            _group setFormation _yeniForm;

            {
                _x setVariable [QEGVAR(main,currentTask), nil, EGVAR(main,debug_functions)];
                _x setVariable [QGVAR(forceMove), nil];
                _x setUnitPos "AUTO";
                _x doWatch objNull;
                _x doFollow (leader _x);
            } forEach (units _group);
        };
    },
    [_group, time + _delay, speedMode _unit, formation _unit, _bndToken]
] call CBA_fnc_waitUntilAndExecute;

// ---------------------------------------------------------------------------
// Hazir birlikleri bul
// ---------------------------------------------------------------------------
if (_units isEqualTo []) then {
    _units = _unit call lambs_main_fnc_findReadyUnits;
};
if (count _units < 4) then {
    _units = (units _group) select {alive _x && {isNull objectParent _x}};
};
if (count _units < 4) exitWith {
    _group setVariable ["lambs_danger_isBounding", nil];
    _group setVariable ["lambs_danger_isExecutingTactic", nil];
    false
};

// ---------------------------------------------------------------------------
// Araclar
// ---------------------------------------------------------------------------
private _vehicles = [_unit] call EFUNC(main,findReadyVehicles);

// ---------------------------------------------------------------------------
// Hedef cevresindeki potansiyel hedefler
// ---------------------------------------------------------------------------
private _posList = [_target, 20, true, false] call EFUNC(main,findBuildings);
_posList append ((nearestTerrainObjects [_target, ["HIDE", "TREE", "BUSH", "SMALL TREE"], 8, false, true]) apply { (getPosATL _x) vectorAdd [0, 0, random 2] });
_posList pushBack _target;

// ---------------------------------------------------------------------------
// Gorev degiskenleri
// ---------------------------------------------------------------------------
_unit setVariable [QEGVAR(main,currentTarget), _target, EGVAR(main,debug_functions)];
_unit setVariable [QEGVAR(main,currentTask), "Tactics Bounding", EGVAR(main,debug_functions)];
_group setVariable [QEGVAR(main,currentTactic), "Bounding Overwatch", EGVAR(main,debug_functions)];

// ---------------------------------------------------------------------------
// Jest + callout
// ---------------------------------------------------------------------------
[_unit, ["gestureGo"]] call EFUNC(main,doGesture);
[_units select -1, "gestureGoB"] call EFUNC(main,doGesture);

private _sonCallout = _group getVariable [QGVAR(bndSonCallout), 0];
if (time - _sonCallout > 60) then {
    [_unit, "combat", "Advance", 125] call EFUNC(main,doCallout);
    _group setVariable [QGVAR(bndSonCallout), time];
};

// ---------------------------------------------------------------------------
// Grubu hazirla
// ---------------------------------------------------------------------------
_group setFormDir (_unit getDir _target);

private _formation = [_unit, _target, "BOUNDING"] call FUNC(selectFormation);
_group setFormation _formation;
_group setVariable [QGVAR(dangerFormation), _formation];

_group enableAttack false;
_units allowGetIn false;
_units doWatch _target;

{
    _x setVariable [QGVAR(forceMove), true];
    _x forceSpeed -1;
} forEach (_units select {isNull objectParent _x});

// ---------------------------------------------------------------------------
// FAZ 2: FIRE TEAM SUBDIVISION
// ---------------------------------------------------------------------------
private _teams = [_group] call FUNC(splitFireTeams);
_teams params ["_fse", "_maneuver", "_reserve"];

if (_fse isEqualTo [] || _maneuver isEqualTo []) then {
    _fse = [];
    _maneuver = [];
    {
        if ((_forEachIndex % 2) isEqualTo 0) then {
            _fse pushBack _x;
        } else {
            _maneuver pushBack _x;
        };
    } forEach _units;
    _reserve = [];
};

if (_fse isEqualTo [] || _maneuver isEqualTo []) exitWith {
    _group setVariable ["lambs_danger_isBounding", nil];
    _group setVariable ["lambs_danger_isExecutingTactic", nil];
    false
};

// ---------------------------------------------------------------------------
// Debug
// ---------------------------------------------------------------------------
if (EGVAR(main,debug_functions)) then {
    ["%1 TACTICS BOUNDING (%2 with %3 units [FSE:%4 MVR:%5 RES:%6] @ %7m)", side _unit, name _unit, count _units, count _fse, count _maneuver, count _reserve, round (_unit distance2D _target)] call EFUNC(main,debugLog);

    private _m  = [_unit,   "tactics bounding", _unit call EFUNC(main,debugMarkerColor), "hd_arrow"]    call EFUNC(main,dotMarker);
    private _mt = [_target, "",                 _unit call EFUNC(main,debugMarkerColor), "hd_objective"] call EFUNC(main,dotMarker);
    {_x setMarkerSizeLocal [0.6, 0.6];} forEach [_m, _mt];
    _m setMarkerDirLocal (_unit getDir _target);
    [{{deleteMarker _x; true} count _this;}, [_m, _mt], _delay + 30] call CBA_fnc_waitAndExecute;
};

// ---------------------------------------------------------------------------
// Bounding dongusunu ayri scheduled thread'de baslat
// ---------------------------------------------------------------------------
[_group, _fse, _maneuver, _reserve, _target, _targetASL, _vehicles, _unit,
 _BND_ASSAULT_RANGE, _BND_CYCLE_BASE, _BND_CYCLE_RAND, _BND_SUPPRESSION_MUL,
 _BND_MAX_CYCLES, _BND_COVER_RANGE, _bndToken] spawn {

    params [
        "_group", "_fse", "_maneuver", "_reserve", "_target", "_targetASL", "_vehicles", "_leader",
        "_BND_ASSAULT_RANGE", "_BND_CYCLE_BASE", "_BND_CYCLE_RAND", "_BND_SUPPRESSION_MUL",
        "_BND_MAX_CYCLES", "_BND_COVER_RANGE", "_bndToken"
    ];

    private _cycleCount = 0;

    // Bounding'i temiz bitirir (bayraklar + enableAttack/allowGetIn/doWatch geri)
    private _bndTemizle = {
        params ["_g"];
        _g setVariable [QGVAR(bndToken), nil];
        _g setVariable [QGVAR(isBounding), nil];
        _g setVariable [QGVAR(isExecutingTactic), nil];
        _g setVariable [QEGVAR(main,currentTactic), nil];
        _g enableAttack true;
        (units _g) allowGetIn true;
        {
            _x setVariable [QGVAR(forceMove), nil];
            _x doWatch objNull;
            _x setUnitPos "AUTO";
        } forEach (units _g);
    };

    if (!GVAR(disableAutonomousSmokeGrenades)) then {
        [_leader, _target] call EFUNC(main,doSmoke);
    };

    // FORMASYON ZORLAMA
    [_group] spawn {
        params ["_g"];
        while {!isNull _g && {_g getVariable ["lambs_danger_isBounding", false]}} do {
            private _df = _g getVariable ["lambs_danger_dangerFormation", ""];
            if (_df isNotEqualTo "" && {formation _g isNotEqualTo _df}) then {
                _g setFormation _df;
            };
            sleep 0.5;
        };
    };

    while {
        !isNull _group
        && {(_group getVariable [QGVAR(isBounding), false])}
        && {(_group getVariable [QGVAR(isExecutingTactic), false])}
        && {(leader _group) distance2D _target > _BND_ASSAULT_RANGE}
        && {{alive _x} count (units _group) >= 2}
        && {_cycleCount < _BND_MAX_CYCLES}
    } do {
        _cycleCount = _cycleCount + 1;

        // KAYIP KONTROLU — komutan her cycle'da yeniden degerlendirir.
        // (fnc_tactics bounding sirasinda komutani cagirmadigi icin eskiden
        //  agir kayipta bile cekilme hic tetiklenmiyordu)
        private _komutanKarar = [_group, _target] call FUNC(commanderAssess);
        if (_komutanKarar in ["WITHDRAW", "PEEL"]) exitWith {
            [_group] call _bndTemizle;
            [_group, _target] call FUNC(tacticsRetreat);
        };

        // FORMASYON KORUMA
        private _bndFormation = _group getVariable [QGVAR(dangerFormation), "WEDGE"];
        private _mevcutFormation = formation _group;
        if (_mevcutFormation isNotEqualTo _bndFormation) then {
            _group setFormation _bndFormation;
            if (EGVAR(main,debug_functions)) then {
                ["[FORMASYON-KORU] %1 | zorla:%2 | onceki:%3", _group, _bndFormation, _mevcutFormation] call EFUNC(main,debugLog);
            };
        };

        // ARAC DEGERLENDIRME
        private _sonPos = _group getVariable [QGVAR(bndSonPos), [0,0,0]];
        private _simdiPos = getPosATL (leader _group);
        private _uzaklik = _sonPos distance2D _simdiPos;

        if (_cycleCount isEqualTo 1 || {_uzaklik > 5}) then {
            _group setVariable [QGVAR(bndSonPos), _simdiPos];
            private _yeniFormasyon = [leader _group, _target, "BOUNDING"] call FUNC(selectFormation);
            if (_yeniFormasyon isNotEqualTo _bndFormation) then {
                _group setVariable [QGVAR(dangerFormation), _yeniFormasyon];
                _group setFormation _yeniFormasyon;
                if (EGVAR(main,debug_functions)) then {
                    ["[FORMASYON-GUNCELLE] %1 | eski:%2 | yeni:%3 | hareket:%4m",
                        _group, _bndFormation, _yeniFormasyon, round _uzaklik] call EFUNC(main,debugLog);
                };
            };
        };

        // Canli birlikleri yeniden ayir
        _fse      = _fse select {alive _x};
        _maneuver = _maneuver select {alive _x};
        _reserve  = _reserve select {alive _x};

        if (count _fse < 2 && {count _reserve > 0}) then {
            _fse pushBack (_reserve deleteAt 0);
        };
        if (count _maneuver < 2 && {count _reserve > 0}) then {
            _maneuver pushBack (_reserve deleteAt 0);
        };

        private _suppressors = _fse;
        private _bounders    = _maneuver;
        private _bekleyenler = _reserve;

        // -------------------------------------------------------------------
        // SUPPRESS kanadi — AGRESIF OVERWATCH
        // -------------------------------------------------------------------
        {
            if (alive _x && {isNull objectParent _x}) then {
                _x setVariable [QEGVAR(main,currentTask), "Bound/Suppress", EGVAR(main,debug_functions)];
                _x doWatch _target;
                [_x, _targetASL] call EFUNC(main,doSuppress);

                // EK: dusmani bul ve kilitle
                private _dusman = _x findNearestEnemy _x;
                if (!isNull _dusman && {_x distance2D _dusman < 400}) then {
                    _x doTarget _dusman;
                };
            };
        } forEach _suppressors;

        // -------------------------------------------------------------------
        // BOUND kanadi — BUDDY RUSH
        // -------------------------------------------------------------------
        if (_bounders isNotEqualTo []) then {

            private _oncelikHesapla = {
                params ["_birim"];
                private _skor = 0;

                private _wpn = primaryWeapon _birim;
                private _wpnType = getNumber (configFile >> "CfgWeapons" >> _wpn >> "type");
                if (_wpnType in [4, 5]) then { _skor = _skor + 100; };

                if ((secondaryWeapon _birim) isNotEqualTo "") then { _skor = _skor + 80; };

                if (_birim isEqualTo (leader (group _birim))) then { _skor = _skor + 60; };
                if (_birim isEqualTo (leader _group)) then { _skor = _skor + 40; };

                _skor
            };

            private _sirali = [];
            private _gecici = +_bounders;
            while {_gecici isNotEqualTo []} do {
                private _enIyiIdx = 0;
                private _enIyiSkor = -1;
                {
                    private _s = [_x] call _oncelikHesapla;
                    if (_s > _enIyiSkor) then {
                        _enIyiSkor = _s;
                        _enIyiIdx = _forEachIndex;
                    };
                } forEach _gecici;
                _sirali pushBack (_gecici select _enIyiIdx);
                _gecici deleteAt _enIyiIdx;
            };

            private _ciftler = [];
            private _idx = 0;
            while {_idx < count _sirali} do {
                private _kalan = (count _sirali) - _idx;
                private _cift = [_sirali select _idx];

                if (_kalan >= 2) then {
                    _cift pushBack (_sirali select (_idx + 1));
                    _ciftler pushBack _cift;
                    _idx = _idx + 2;
                } else {
                    if (_ciftler isNotEqualTo []) then {
                        private _sonCift = _ciftler select ((count _ciftler) - 1);
                        _sonCift pushBack (_sirali select _idx);
                    } else {
                        _ciftler pushBack _cift;
                    };
                    _idx = _idx + 1;
                };
            };

            {
                private _cift = _x;
                private _ciftIdx = _forEachIndex;
                private _ciftBoyut = count _cift;

                if (_ciftBoyut isEqualTo 1) then {
                    private _tek = _cift select 0;
                    if (alive _tek && {isNull objectParent _tek}) then {
                        _tek setVariable [QEGVAR(main,currentTask), "BuddyRush/Overwatch", EGVAR(main,debug_functions)];
                        _tek doWatch _target;
                        [_tek, _targetASL] call EFUNC(main,doSuppress);

                        private _dusmanTek = _tek findNearestEnemy _tek;
                        if (!isNull _dusmanTek && {_tek distance2D _dusmanTek < 400}) then {
                            _tek doTarget _dusmanTek;
                        };

                        if (EGVAR(main,debug_functions)) then {
                            diag_log format [
                                "[BUDDY-RUSH] %1 | cift:%2 | tek:%3 | overwatch",
                                groupId _group, _ciftIdx, name _tek
                            ];
                        };
                    };
                } else {
                    private _siraliCift = [];
                    private _geciciCift = +_cift;
                    while {_geciciCift isNotEqualTo []} do {
                        private _enKotuIdx = 0;
                        private _enKotuSkor = 99999;
                        {
                            private _s = [_x] call _oncelikHesapla;
                            if (_s < _enKotuSkor) then {
                                _enKotuSkor = _s;
                                _enKotuIdx = _forEachIndex;
                            };
                        } forEach _geciciCift;
                        _siraliCift pushBack (_geciciCift select _enKotuIdx);
                        _geciciCift deleteAt _enKotuIdx;
                    };

                    private _kosanIdx = _cycleCount % (count _siraliCift);
                    private _kosan = _siraliCift select _kosanIdx;
                    private _destekler = [];
                    {
                        if (_forEachIndex isNotEqualTo _kosanIdx) then {
                            _destekler pushBack _x;
                        };
                    } forEach _siraliCift;

                    // KOSAN — moveTo ile guclu hareket
                    if (alive _kosan && {isNull objectParent _kosan} && {(vehicle _kosan) isEqualTo _kosan}) then {
                        private _cover = [_kosan, _target, _BND_COVER_RANGE, "ASCEND", 1] call EFUNC(main,findCover);
                        private _movePos = _target;
                        private _stance  = "AUTO";

                        if (_cover isNotEqualTo []) then {
                            private _coverData = _cover select 0;
                            _movePos = _coverData select 0;
                            _stance  = _coverData select 1;
                        };

                        _kosan setVariable [QEGVAR(main,currentTask), "BuddyRush/Move", EGVAR(main,debug_functions)];
                        _kosan setUnitPosWeak _stance;
                        _kosan moveTo _movePos;
                        _kosan doWatch _target;
                        _kosan forceSpeed -1;
                    };

                    // DESTEKLER
                    {
                        if (alive _x && {isNull objectParent _x}) then {
                            _x setVariable [QEGVAR(main,currentTask), "BuddyRush/Overwatch", EGVAR(main,debug_functions)];
                            _x doWatch _target;
                            [_x, _targetASL] call EFUNC(main,doSuppress);

                            private _dusman = _x findNearestEnemy _x;
                            if (!isNull _dusman && {_x distance2D _dusman < 400}) then {
                                _x doTarget _dusman;
                            };
                        };
                    } forEach _destekler;

                    if (EGVAR(main,debug_functions)) then {
                        diag_log format [
                            "[BUDDY-RUSH] %1 | cycle:%2 | cift:%3 | boyut:%4 | kosan:%5 | destek:%6",
                            groupId _group, _cycleCount, _ciftIdx, _ciftBoyut,
                            if (isNull _kosan) then {"yok"} else {name _kosan},
                            count _destekler
                        ];
                    };
                };
            } forEach _ciftler;
        };

        // Araclar
        { _x doMove _target; } forEach _vehicles;

        // Adaptif zamanlama
        private _maxSuppression = 0;
        {
            private _sup = getSuppression _x;
            if (_sup > _maxSuppression) then {_maxSuppression = _sup;};
        } forEach _bounders;

        private _sleepTime = _BND_CYCLE_BASE
                           + random _BND_CYCLE_RAND
                           + (_maxSuppression * _BND_SUPPRESSION_MUL);

        sleep _sleepTime;

        private _sonCycleCallout = _group getVariable [QGVAR(bndSonCycleCallout), 0];
        if ((time - _sonCycleCallout > 90) && RND(0.5)) then {
            [leader _group, "combat", "Advance", 125] call EFUNC(main,doCallout);
            _group setVariable [QGVAR(bndSonCycleCallout), time];
        };
    };

    // Dongu bitti — token eslesiyorsa bu bounding hala bizim (Retreat devralmadi)
    if (
        !isNull _group
        && {(_group getVariable [QGVAR(bndToken), ""]) isEqualTo _bndToken}
    ) then {
        private _yakin = ((leader _group) distance2D _target < (_BND_ASSAULT_RANGE + 10))
            && {({alive _x} count (units _group)) >= 2};
        [_group] call _bndTemizle;
        if (_yakin) then {
            [_group, _target] call FUNC(tacticsAssault);
        } else {
            // Cycle limiti doldu / hedef uzak: kilidi birak, gruba normal davranisi geri ver
            { if (alive _x) then { _x doFollow (leader _x); }; } forEach (units _group);
        };
    };
};

// end
true