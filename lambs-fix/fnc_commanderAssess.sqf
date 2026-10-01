#include "script_component.hpp"
/*
 * Author: Cinar (ELITE fork)
 * Komutan Beyni — 5 faktor tehdit analizi + NATO karar tablosu
 * LAMBS'in "random 1 < 0.85" zar atma yerine gercek karar verir.
 *
 * Arguments:
 * 0: group <GROUP> or group leader <OBJECT>
 * 1: known enemy target <OBJECT> or position <ARRAY>
 *
 * Return Value:
 * Decision string <STRING>:
 *   "WITHDRAW" | "HOLD" | "DELAY" | "SUPPRESS_ASSAULT"
 *   | "FLANK" | "ASSAULT" | "BOUNDING" | "PEEL"
 *
 * Debug HUD legend (systemChat):
 *   [CMD] <leader> [<own>v<enemy>] Cnt:Fir:Cas:Amm:Pos | THR:<score> | <decision> (<reason>)
 *   Cnt = sayi faktoru (0=az tehdit, 1=cok tehdit)
 *   Fir = dusman ates gucu faktoru
 *   Cas = kendi kayip faktoru
 *   Amm = kendi muhimmat faktoru (1=bos)
 *   Pos = pozisyon faktoru (1=acik, 0=bina)
 *
 * Example:
 * [bob, angryJoe] call lambs_danger_fnc_commanderAssess;
 *
 * Public: No
*/

params [
    ["_group", grpNull, [grpNull, objNull]],
    ["_target", objNull, [objNull, []]]
];

// ---------------------------------------------------------------------------
// Normalize ONCE — spam korumasi gruba yazmali, unite degil
// ---------------------------------------------------------------------------
if (_group isEqualType objNull) then {_group = group _group;};
if (isNull _group) exitWith {"BOUNDING"};
if ((units _group) isEqualTo []) exitWith {"BOUNDING"};

private _unit = leader _group;
if (isNull _unit) exitWith {"BOUNDING"};

// ---------------------------------------------------------------------------
// HEDEF NORMALIZE — _targetPos burada tanimlanir, sonra kullanilir
// ---------------------------------------------------------------------------
private _targetPos = _target call CBA_fnc_getPos;
if ((_targetPos select 2) > 6) then {_targetPos set [2, 0.5];};

// ---------------------------------------------------------------------------
// SPAM KORUMASI — ayni grup icin 3 sn icinde 2. kez karar verme
// ---------------------------------------------------------------------------
private _sonZaman = _group getVariable [QGVAR(cmdLastEval), 0];
if (time - _sonZaman < 3) exitWith {
    _group getVariable [QGVAR(cmdLastDecision), "BOUNDING"]
};
_group setVariable [QGVAR(cmdLastEval), time];

// ---------------------------------------------------------------------------
// Temel veriler
// ---------------------------------------------------------------------------
private _aliveUnits = (units _group) select {alive _x};
private _ownCount = count _aliveUnits;
if (_ownCount <= 0) exitWith {"WITHDRAW"};

private _mySide = side _unit;
private _distance = _unit distance2D _targetPos;

// ---------------------------------------------------------------------------
// FAKTOR 1 — DUSMAN SAYISI  (agirlik %25)
// 300m icindeki bilinen dusmanlar
// ---------------------------------------------------------------------------
private _nearAll = _unit nearEntities ["CAManBase", 300];
private _enemies = _nearAll select {
    alive _x
    && {!((side _x) == civilian)}
    && {(_mySide getFriend (side _x)) < 0.6}
};

private _enemyCount = count _enemies;
private _countRatio = _enemyCount / (_ownCount max 1);
private _factorCount = linearConversion [0.5, 2.0, _countRatio, 0.2, 1.0, true];

// ---------------------------------------------------------------------------
// FAKTOR 2 — DUSMAN ATES GUCU  (agirlik %20)
// MG (type 4) / Sniper (type 5) / Launcher
// ---------------------------------------------------------------------------
private _firepower = 0;
private _hasHeavyWeapon = false;
{
    private _wpn = primaryWeapon _x;
    if (_wpn isNotEqualTo "") then {
        private _wpnType = getNumber (configFile >> "CfgWeapons" >> _wpn >> "type");
        if (_wpnType in [4, 5]) then {
            _firepower = _firepower + 1;
            _hasHeavyWeapon = true;
        };
    };
    if ((secondaryWeapon _x) isNotEqualTo "") then {
        _firepower = _firepower + 1.5;
        _hasHeavyWeapon = true;
    };
} forEach _enemies;

private _factorFirepower = linearConversion [0, 3, _firepower, 0.2, 1.0, true];

// ---------------------------------------------------------------------------
// FAKTOR 3 — KENDI KAYIP  (agirlik %20)
// cmdInitialCount XEH_postInit.sqf'te her gruba spawn'da set edilir.
// Bulletproof: nil donebilir, SQF quirk'i yuzunden kontrol edilir.
// ---------------------------------------------------------------------------
private _initialCount = _group getVariable [QGVAR(cmdInitialCount), -1];

// BULLETPROOF: getVariable nil donebilir, private _x = nil sonrasi _x
// undefined olur (SQF quirk). Bu yuzden iki katmanli kontrol.
if (isNil "_initialCount") then { _initialCount = -1; };
if !(_initialCount isEqualType 0) then { _initialCount = -1; };

if (_initialCount < 0) then {
    _initialCount = _ownCount;
    _group setVariable [QGVAR(cmdInitialCount), _initialCount];
};

private _lossRatio = 0;
if (_initialCount > 0) then {
    _lossRatio = (_initialCount - _ownCount) / _initialCount;
};
private _factorCasualty = linearConversion [0, 0.5, _lossRatio, 0, 1, true];

// ---------------------------------------------------------------------------
// FAKTOR 4 — KENDI MUHIMMAT  (agirlik %15)
// 2026-09-30 FIX: needReload yaniltici (bos sarjorde 0 donuyor).
// Artik magazinesAmmoFull ile GERCEK toplam mermi sayisi olculur.
// ---------------------------------------------------------------------------
// GERCEK CEPHANE — mermi/kisi orani (baseline yok, mutlak esik)
// 2026-09-30 fix v2: baseline bug'i (bos grup yanlis referans aliyor)
private _toplamMermi = 0;
{
    private _asker = _x;
    {
        _x params ["_magClass", "_ammoCount"];
        // 2026-10-01 FIX: magazinesAmmoFull'un 4. elemani sayi, konum 5. elemandi
        // -> sadece takili sarjor sayiliyordu, grup ates acinca hep HOLD'a dusuyordu.
        // magazinesAmmo: TUM sarjorler. >1 filtresi el bombasi/roket/fume atar.
        if (_ammoCount > 1) then {
            _toplamMermi = _toplamMermi + _ammoCount;
        };
    } forEach (magazinesAmmo _asker);
} forEach _aliveUnits;

// Mermi/kisi orani (30 mermi = 1 sarjor)
private _mermiPerKisi = _toplamMermi / (_ownCount max 1);

// Esikler (asker basi mermi):
//   > 90  -> 0.2 bol (3+ sarjor)
//   60-90 -> 0.4 normal (2 sarjor)
//   30-60 -> 0.6 az (1 sarjor)
//   10-30 -> 0.85 kritik
//   < 10  -> 1.0 bitti
private _factorAmmo = switch (true) do {
    case (_mermiPerKisi < 10):  { 1.00 };
    case (_mermiPerKisi < 30):  { 0.85 };
    case (_mermiPerKisi < 60):  { 0.60 };
    case (_mermiPerKisi < 90):  { 0.40 };
    default                     { 0.20 };
};

// _ammoOran: geriye uyumluluk ve cephane kurali icin
// 0.0 = bitti, 1.0 = dolu
private _ammoOran = switch (true) do {
    case (_mermiPerKisi < 10):  { 0.05 };
    case (_mermiPerKisi < 30):  { 0.20 };
    case (_mermiPerKisi < 60):  { 0.50 };
    case (_mermiPerKisi < 90):  { 0.75 };
    default                     { 1.00 };
};

private _reloadAvg = 1 - _ammoOran;  // geriye uyumluluk
// ---------------------------------------------------------------------------
// FAKTOR 5 — POZISYON  (agirlik %20)
// Bina = iyi savunma (dusuk tehdit), Acik = kotu (yuksek tehdit)
// ---------------------------------------------------------------------------
private _leaderPos = getPosATL _unit;
private _buildings = nearestTerrainObjects [
    _leaderPos,
    ["BUILDING", "HOUSE", "CHURCH", "FUELSTATION", "HOSPITAL"],
    50, false, true
];
private _trees = nearestTerrainObjects [
    _leaderPos, ["TREE", "SMALL TREE", "BUSH"], 30, false, true
];
private _isUrban  = (count _buildings) >= 8;
private _isForest = (count _trees) >= 12 && {!_isUrban};

private _factorPosition = if (_isUrban) then {0.2} else {
    if (_isForest) then {0.5} else {0.8}
};

// ---------------------------------------------------------------------------
// AGIRLIKLI TEHDIT SKORU (bilgilendirici — karar tablosu bunu kullanmiyor)
// %25 sayi + %20 ates gucu + %20 kayip + %15 muhimmat + %20 pozisyon
// ---------------------------------------------------------------------------
private _threatScore =
    (_factorCount     * 0.25) +
    (_factorFirepower * 0.20) +
    (_factorCasualty  * 0.20) +
    (_factorAmmo      * 0.15) +
    (_factorPosition  * 0.20);

// ---------------------------------------------------------------------------
// KONTROL: Dusman binada mi?
// ---------------------------------------------------------------------------
private _enemyInBuilding = false;
{
    if ((_x distance2D _targetPos) < 30) then {
        private _b = nearestTerrainObjects [getPosATL _x, ["BUILDING", "HOUSE"], 5, false, true];
        if ((count _b) > 0) exitWith { _enemyInBuilding = true; };
    };
} forEach _enemies;

// ---------------------------------------------------------------------------
// KARAR TABLOSU — oncelik sirali (en tepeden asagi)
// call {} + exitWith pattern: her blok ilk eslesen karari doner
// ---------------------------------------------------------------------------
private _result = [
    _lossRatio, _reloadAvg, _enemyCount, _ownCount,
    _distance, _enemyInBuilding, _hasHeavyWeapon, _ammoOran, _mermiPerKisi
] call {
       params [
        "_lossRatio", "_reloadAvg", "_enemyCount", "_ownCount",
        "_distance", "_enemyInBuilding", "_hasHeavyWeapon", "_ammoOran", "_mermiPerKisi"
    ];

    // =======================================================================
    // CEPHANE — en kritik (doktrin: mermisi olmayan asker cekilir)
    // =======================================================================
        if (_ammoOran <= 0.1) exitWith {
        ["WITHDRAW", format ["cephane bitti (mermi/kisi: %1)", round _mermiPerKisi]]
    };
    if (_ammoOran <= 0.25) exitWith {
        ["HOLD", format ["cephane kritik (mermi/kisi: %1)", round _mermiPerKisi]]
    };

    // =======================================================================
    // KAYIP — agir
    // =======================================================================
    if (_lossRatio >= 0.4) exitWith {
        ["WITHDRAW", format ["agir kayip %1%%", round (_lossRatio * 100)]]
    };
    if (_enemyCount >= (_ownCount * 3) && {_lossRatio >= 0.2}) exitWith {
        ["WITHDRAW", format ["3x dezavantaj %1v%2 + kayip %3%%", _enemyCount, _ownCount, round (_lossRatio * 100)]]
    };

    // =======================================================================
    // PEEL — 2:1 dezavantaj + %10 kayip + yakin temas (NATO doktrini)
    // =======================================================================
    if (_enemyCount >= (_ownCount * 2)
        && {_lossRatio >= 0.1}
        && {_distance <= 250}
        && {_distance >= 25}) exitWith {
        ["PEEL", format ["2x dezavantaj %1v%2 + kayip %3%%", _enemyCount, _ownCount, round (_lossRatio * 100)]]
    };

    // PEEL — %15+ kayip
    if (_lossRatio >= 0.15 && {_lossRatio < 0.4}
        && {_distance >= 25} && {_distance <= 250}
        && {_enemyCount > 0}) exitWith {
        ["PEEL", format ["kayip %1%% temas %2m", round (_lossRatio * 100), round _distance]]
    };

    // =======================================================================
    // DIGER KARARLAR
    // =======================================================================
    if (_reloadAvg > 0.75) exitWith {
        ["HOLD", format ["muhimmat az (reload %1)", round (_reloadAvg * 100)]]
    };
    if (_enemyCount >= (_ownCount * 2)) exitWith {
        ["DELAY", format ["dusman 2x ustun (%1v%2)", _enemyCount, _ownCount]]
    };
    if (_distance > 250) exitWith {
        ["FLANK", format ["uzak mesafe %1m", round _distance]]
    };
    if (_enemyInBuilding) exitWith {
        ["SUPPRESS_ASSAULT", "dusman binada"]
    };
    if (_hasHeavyWeapon) exitWith {
        ["FLANK", "dusman MG/AT"]
    };
    if (_enemyCount > 0 && {_ownCount >= (_enemyCount * 1.5)}) exitWith {
        ["ASSAULT", format ["biz 1.5x ustun (%1v%2)", _ownCount, _enemyCount]]
    };
    if (_distance < 60) exitWith {
        ["ASSAULT", format ["yakin mesafe %1m", round _distance]]
    };
    ["BOUNDING", "standart"]
};

private _decision = _result select 0;
private _reason   = _result select 1;

// ---------------------------------------------------------------------------
// TAKTIK HAFIZASI + GRUP KOORDINASYONU
// 1. Ayni grup son 30 sn icinde ayni taktigi tekrarlarsa -> alternatif
// 2. Ayni tarafta baska grup ayni taktigi kullaniyorsa -> alternatif
// WITHDRAW/HOLD/DELAY/SUPPRESS_ASSAULT/PEEL korunur (kritik kararlar)
// ---------------------------------------------------------------------------
private _sonKarar = _group getVariable [QGVAR(cmdSonKarar), ""];
private _sonKararZaman = _group getVariable [QGVAR(cmdSonKararZaman), 0];
private _tekrarMi = (_sonKarar isEqualTo _decision) && {(time - _sonKararZaman) < 30};

private _digerAyni = false;
if (!_tekrarMi && {_decision in ["BOUNDING", "FLANK", "ASSAULT"]}) then {
    {
        if (
            _x isNotEqualTo _group
            && {side _x isEqualTo _mySide}
            && {count units _x >= 4}
        ) then {
            private _k = _x getVariable [QGVAR(cmdSonKarar), ""];
            private _z = _x getVariable [QGVAR(cmdSonKararZaman), 0];
            if ((time - _z) < 25 && {_k isEqualTo _decision}) exitWith {
                _digerAyni = true;
            };
        };
    } forEach allGroups;
};

if ((_tekrarMi || _digerAyni) && {_decision in ["BOUNDING", "FLANK", "ASSAULT"]}) then {
    _decision = switch (_decision) do {
        case "BOUNDING": { "FLANK" };
        case "FLANK":    { "SUPPRESS_ASSAULT" };
        case "ASSAULT":  { "BOUNDING" };
        default          { _decision };
    };
    _reason = if (_tekrarMi) then {
        "hafiza: alternatif"
    } else {
        "koord: farkli grup"
    };
};

// Karari kaydet (hafiza + koordinasyon icin)
_group setVariable [QGVAR(cmdSonKarar), _decision];
_group setVariable [QGVAR(cmdSonKararZaman), time];

// ---------------------------------------------------------------------------
// DEBUG — systemChat + diag_log
// ---------------------------------------------------------------------------
if (EGVAR(main,debug_functions)) then {
    private _msg = format [
        "[CMD] %1 [%2v%3] Cnt:%4 Fir:%5 Cas:%6 Amm:%7 Pos:%8 | THR:%9 | %10 (%11)",
        name _unit,
        _ownCount, _enemyCount,
        _factorCount     toFixed 2,
        _factorFirepower toFixed 2,
        _factorCasualty  toFixed 2,
        _factorAmmo      toFixed 2,
        _factorPosition  toFixed 2,
        _threatScore     toFixed 2,
        _decision, _reason
    ];
    systemChat _msg;
    diag_log _msg;
};

// ---------------------------------------------------------------------------
// Grup degiskenleri — diger fonksiyonlar / test icin
// ---------------------------------------------------------------------------
_group setVariable [QGVAR(cmdLastThreat),   _threatScore];
_group setVariable [QGVAR(cmdLastDecision), _decision];
_group setVariable [QGVAR(cmdFactors), [
    _factorCount, _factorFirepower, _factorCasualty, _factorAmmo, _factorPosition
]];

_decision