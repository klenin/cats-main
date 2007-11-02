/* http://calendar.swazz.org */

function $(id) {
	if (document.getElementById) return document.getElementById(id);
	else if (document.all) return document.all[id];
	else if (document.layers) return document.layers[id];
}

function eventTarget(e) {
	var evt = e ? e : window.event;
	var el = evt.target ? evt.target : evt.srcElement;
	if (el.nodeType == 3) el = el.parentNode; // defeat Safari bug
	return el;
}

function checkClick(e) {
	var fc = $('fc');
	if (fc && !isChild(eventTarget(e), fc))
		fc.style.display = 'none';
}

function isChild(s, d) {
	while (s) {
		if (s == d) return true;
		s = s.parentNode;
	}
	return false;
}

// Calendar script
var oldDate = new Date;
var curDate = new Date;
var dateField;

function genCalendar() {
	document.write(
		'<table id="fc" class="calendar" style="display:none" cellpadding="2">' +
		'<tr><td style="cursor:pointer" onclick="caddm(-1)"><img src="img/arrowleftmonth.gif"></td>' +
		'<td colspan=5 id="mns"></td>' +
		'<td style="cursor:pointer" onclick="caddm(1)"><img src="img/arrowrightmonth.gif"></td></tr>');
		
	//('M','T','W','T','F','S','S');
	var weekDays = new Array('&#1055;','&#1042;','&#1057;','&#1063;','&#1055;','&#1057;','&#1042;');
	document.write('<tr id="weekdays">');
	for (var wd = 0; wd < weekDays.length; ++wd)
		document.write('<td>' + weekDays[wd] + '</td>');
	document.write('</tr>');
	for (var kk = 1; kk <= 6; kk++) {
		document.write('<tr class="calrow">');
		for (var tt = 1; tt <= 7; tt++) {
			num = 7 * (kk-1) - (-tt);
			document.write('<td id="v' + num + '">&nbsp;' + num + '</td>');
		}
		document.write('</tr>');
	}
	document.write('</table>');

	document.all ? document.attachEvent('onclick', checkClick) : document.addEventListener('click', checkClick, false);
	prepCalendar();
}

function bottomLeftPos(elem) {
	if (elem.getBoundingClientRect) {
		var r = elem.getBoundingClientRect();
		return { "left": r.left, "top": r.bottom };
	}
	if (document.getBoxObjectFor) {
		var b = document.getBoxObjectFor(elem);
		return { "left": b.x, "top": b.y + b.height };
	}
	alert('!');
}

function showCalendar(elem, e) {
	e = e ? e : window.event;
	e.cancelBubble = true;
	if (e.stopPropagation) e.stopPropagation();
	dateField = elem;
	dateField.select();

	var p = bottomLeftPos(dateField);
	$('fc').style.left = p.left + 'px';
	$('fc').style.top = p.top + 'px';
	$('fc').style.display = '';
	
	// Validate date
	var dateParts = dateField.value.split('.'); // day.month.year
	if (dateParts.length != 3) return;

	for (var k = 0; k < 3; ++k)
		if (isNaN(dateParts[k])) return;

	oldDate = new Date(dateParts[2], dateParts[1] - 1, dateParts[0]);
	curDate = new Date(oldDate.getFullYear(), oldDate.getMonth(), 1);
	prepCalendar();
}

function cs_over(e) {
	var t = eventTarget(e);
	t.className = t.className + ' over';
}

function cs_out(e) {
	var t = eventTarget(e);
	t.className = t.className.replace(/\s*over\s*/, '');
}

function cs_click(e) {
	var t = eventTarget(e);
	var cy = curDate.getFullYear();
	var cm = curDate.getMonth() + 1;
	dateField.value = ('0' + t.innerHTML).slice(-2) + '.' + ('0' + cm).slice(-2) + '.' + cy;
	$('fc').style.display = 'none';
}

function prepCalendar() {
	var monthNames = new Array(
		'&#1071;&#1053;&#1042;','&#1060;&#1045;&#1042;','&#1052;&#1040;&#1056;',
		'&#1040;&#1055;&#1056;','&#1052;&#1040;&#1049;','&#1048;&#1070;&#1053;',
		'&#1048;&#1070;&#1051;','&#1040;&#1042;&#1043;','&#1057;&#1045;&#1053;',
		'&#1054;&#1050;&#1058;','&#1053;&#1054;&#1071;','&#1044;&#1045;&#1050;'
	); //'JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC');
	var cd = (curDate.getDay() + 6) % 7; // week starts on Monday
	var cy = curDate.getFullYear();
	var cm = curDate.getMonth();
	$('mns').innerHTML = monthNames[cm] + ' ' + cy;
	for (var d = 1; d <= 42; d++) {
		var cell = $('v' + d);
		cell.className = '';
		if (cd + 1 <= d && d <= cd + (32 - new Date(cy, cm, 32).getDate())) {
			var td = new Date(cy, cm, d - cd);
			if (td <= oldDate && td >= oldDate)
				cell.className = 'sel';
			else if (td < (new Date()))
				cell.className = 'past';

			cell.onmouseover = cs_over;
			cell.onmouseout = cs_out;
			cell.onclick = cs_click;
			cell.innerHTML = td.getDate();
			cell.style.cursor = 'pointer';
		}
		else {
			cell.onmouseover = null;
			cell.onmouseout = null;
			cell.onclick = null;
			cell.innerHTML = '&nbsp;';
			cell.style.cursor = 'default';
		}
	}
}

function caddm(delta) {
	curDate.setMonth(curDate.getMonth() + delta);
	prepCalendar();
}
