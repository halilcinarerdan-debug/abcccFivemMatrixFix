#include "script_component.hpp"
/*
 * Author: Cinar (ELITE fork)
 * Arazi tipine ve duruma gore en uygun formasyonu secer.
 * LOS kontrolu kaldirildi (ceset/bodybag VIEW filtresini kirletiyordu).
 *
 * Arguments:
 * 0: lider birim <OBJECT> veya grup <GROUP>
 * 1: hedef <OBJECT> veya pozisyon <ARRAY>
 * 2: baglam <STRING> - "BOUNDING" | "ASSAULT" | "TRAVEL" | "DEFENSE"
 *
 * Return Value:
 * Formasyon ismi <STRING>
 *
 * Public: No
*/

params [
    ["_unit", objNull, [objNull, grpNull]],
    ["_target", [0, 0, 0], [objNull, []]],
    ["_context", "BOUNDING", [""]]
];

// ---------------------------------------------------------------------------
// Grup normalize
// ---------------------------------------------------------------------------
if (_unit isEqualType grpNull) then {_unit = leader _unit;};
if (isNull _unit) exitWith {"WEDGE"};

// ---------------------------------------------------------------------------
// PEEL KONTROLU — Peel aktifken FILE'dan baska formasyon secme
// ---------------------------------------------------------------------------
private _grpKontrol = group _unit;
if (!isNull _grpKontrol && {_grpKontrol getVariable [QGVAR(isPeeling), false]}) exitWith {
    if (EGVAR(main,debug_functions)) then {
        diag_log format ["[FORMASYON] %1 | PEEL AKTIF | FILE kilidi", name _unit];
    };
    "FILE"
};
// ---------------------------------------------------------------------------
// RETREAT KONTROLU — Geri cekilme sirasinda FILE'dan baska formasyon secme
// (yukaridaki ikinci/cift PEEL blogu kaldirildi)
// ---------------------------------------------------------------------------
if (!isNull _grpKontrol && {_grpKontrol getVariable [QGVAR(isRetreating), false]}) exitWith {
    "FILE"
};
// ---------------------------------------------------------------------------
// Hedef pozisyon (obje veya dizi olabilir)
// ---------------------------------------------------------------------------
private _targetPos = [0, 0, 0];
private _validTarget = true;

if (_target isEqualType objNull) then {
    if (isNull _target) then {
        _validTarget = false;
    } else {
        _targetPos = getPosATL _target;
    };
} else {
    if (_target isEqualType []) then {
        if (count _target < 2) then {
            _validTarget = false;
        } else {
            _targetPos = _target;
        };
    } else {
        _validTarget = false;
    };
};

if (!_validTarget) exitWith {"WEDGE"};

// ---------------------------------------------------------------------------
// ARAZI TESPIT POZISYONU — Lider degil, GRUP MERKEZI
// Bounding'de lider arkada kalabilir (suppress), bound kanadi one gider.
// Grup ortalama pozisyonu gercek "neredeyiz" sorusuna cevap verir.
// ---------------------------------------------------------------------------
private _grup = if (_unit isEqualType grpNull) then {_unit} else {group _unit};
private _birimler = (units _grup) select {alive _x};

private _leaderPos = [0, 0, 0];
if (_birimler isNotEqualTo []) then {
    private _toplam = [0, 0, 0];
    {
        _toplam = _toplam vectorAdd (getPosATL _x);
    } forEach _birimler;
    _leaderPos = _toplam vectorMultiply (1 / (count _birimler));
} else {
    _leaderPos = getPosATL _unit;
};

// ===========================================================================
// ARAZI TESPITI (LOS KONTROLU YOK)
// ===========================================================================


// ===========================================================================
// ARAZI TESPITI — GENIS ALAN, DAR ESIK
// - BUSH'lar CIKARILDI (gorunmez, yaniltiyordu)
// - Yaricap 2x BUYUTULDU (50→80, 30→60)
// - Oncelik sirasi: URBAN > FOREST > OPEN
// - Urban esigi DUSURULDU (8→5)
// ===========================================================================

// 1) Bina yogunlugu — 80m yaricap (genis alan)
private _buildings = nearestTerrainObjects [
    _leaderPos,
    ["BUILDING", "HOUSE", "CHURCH", "FUELSTATION", "HOSPITAL"],
    80, false, true
];
private _buildingCount = count _buildings;

// 2) Agac yogunlugu — 60m yaricap, BUSH YOK
private _trees = nearestTerrainObjects [
    _leaderPos,
    ["TREE", "SMALL TREE"],   // BUSH CIKARILDI
    60, false, true
];
private _treeCount = count _trees;

// 3) Arazi tipi — ONCELIK SIRASI onemli
private _isUrban  = _buildingCount >= 5;    // 8 → 5 (koyu de yakalar)
private _isForest = !_isUrban && {_treeCount >= 20};   // 12 → 20, sadece urban degilse
private _isOpen   = !_isUrban && {!_isForest};

// Debug icin: yeni esikleri logla
if (EGVAR(main,debug_functions)) then {
    diag_log format [
        "[ARAZI-TARAMA] konum:%1 | bina:%2 (esik:5) | agac:%3 (esik:20) | urban:%4 forest:%5",
        _leaderPos, _buildingCount, _treeCount, _isUrban, _isForest
    ];
};

// 4) Yol yakinligi
private _roads = _leaderPos nearRoads 20;
private _onRoad = _roads isNotEqualTo [];

// ===========================================================================
// FORMASYON SECIMI
// ===========================================================================

private _formation = "WEDGE";
private _reason = "default";

switch (_context) do {
    // BOUNDING
    case "BOUNDING": {
        if (_isUrban) then {
            _formation = "DIAMOND";
            _reason = "meskun mahal - her yone bakis";
        } else {
            if (_isForest) then {
                _formation = "FILE";
                _reason = "orman - dar gecis";
            } else {
                _formation = "LINE";
                _reason = "acik arazi - genis cephe";
            };
        };
    };

    // ASSAULT
    case "ASSAULT": {
        if (_isUrban) then {
            _formation = "WEDGE";
            _reason = "CQB - hizli ilerleme";
        } else {
            _formation = "LINE";
            _reason = "acik arazi - ates gucu";
        };
    };

    // TRAVEL
    case "TRAVEL": {
        if (_onRoad) then {
            _formation = "COLUMN";
            _reason = "yol - konvoy duzeni";
        } else {
            if (_isForest) then {
                _formation = "STAG COLUMN";
                _reason = "orman - konvoy";
            } else {
                _formation = "WEDGE";
                _reason = "acik arazi intikal";
            };
        };
    };

    // DEFENSE
    case "DEFENSE": {
        if (_isUrban) then {
            _formation = "DIAMOND";
            _reason = "meskun savunma - her yone";
        } else {
            _formation = "VEE";
            _reason = "acik savunma - agir silah merkezde";
        };
    };

    default {
        _formation = "WEDGE";
        _reason = "bilinmeyen baglam";
    };
};

// ===========================================================================
// DEBUG
// ===========================================================================
if (EGVAR(main,debug_functions)) then {
    ["[FORMASYON] %1 | baglam:%2 | secim:%3 | sebep:%4 | bina:%5 agac:%6 yol:%7",
        name _unit, _context, _formation, _reason,
        _buildingCount, _treeCount,
        ["yok", "var"] select _onRoad
    ] call EFUNC(main,debugLog);
};

_formation