.pragma library
// أدوات نصية: أرقام عربية + تطبيع البحث

var AR = ["٠","١","٢","٣","٤","٥","٦","٧","٨","٩"];

function ar(n) {
    var s = String(n), o = "";
    for (var i = 0; i < s.length; i++) {
        var c = s[i];
        if (c >= "0" && c <= "9") o += AR[+c]; else o += c;
    }
    return o;
}

// إزالة التشكيل والعلامات وتوحيد الحروف — يطابق منطق أدوات البناء
function normAr(s) {
    if (!s) return "";
    s = s.replace(/[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u08D3-\u08FF\u200E\u200F\uFEFF]/g, "");
    s = s.replace(/\u0640/g, "");
    s = s.replace(/[\u0623\u0625\u0622\u0671]/g, "\u0627");
    s = s.replace(/\u0649/g, "\u064A").replace(/\u0629/g, "\u0647");
    s = s.replace(/\u0624/g, "\u0648").replace(/\u0626/g, "\u064A").replace(/\u0621/g, "");
    s = s.replace(/\s+/g, " ").replace(/^ +| +$/g, "");
    return s;
}
