
function $(id) {
    if (document.getElementById) return document.getElementById(id);
    else if (document.all) return document.all[id];
    else if (document.layers) return document.layers[id];
}

var ws = false, ranks;

function ws_replace(s) {
    var ca = s.getElementsByTagName('code');
    for (var i = 0; i < ca.length; ++i) {
        var t = ca[i].innerHTML;
        if (ws)
            t = t.replace(/\u2423/g, ' ');
        else
            t = t.replace(/ /g, '\u2423');
        ca[i].innerHTML = t;
    }
}

function ws_toggle() {
    for (var i = 0; i < ranks.length; ++i)
        ws_replace($('sample' + ranks[i]));
    ws = !ws;
}

function ws_init(title, r) {
    ranks = r;
    document.write('<input type="button" class="button jsonly" onclick="ws_toggle()" value="' + title + '" />');
}
