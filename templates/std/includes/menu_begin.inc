<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html><head>
<meta name="Content-Type" content="text/html; charset=<TMPL_VAR encoding>">
<link rel="shortcut icon" href="images/std/favicon.ico" type="image/x-icon" />
<title><TMPL_VAR contest_title ESCAPE=HTML><TMPL_IF title_suffix> - <TMPL_VAR title_suffix></TMPL_IF></title>
<TMPL_IF refresh>
<meta http-equiv="Refresh" CONTENT="<TMPL_VAR refresh>">
</TMPL_IF>
<link rel="stylesheet" type="text/css" href="./docs/std/main.css">
</head>
<body>
<table class="iface">
  <tr bgcolor="#ffcc55" style="padding-bottom: 2px; height: 69px">
	<td class="top" rowspan="2" width="1%">
	    <img src="./images/std/logo.gif" border="0" alt="CATS">
	</td>
	<td valign="bottom" width="98%">
	    <TMPL_IF contest_title><font size="5" color="#333300"><TMPL_VAR contest_title></font>
      <TMPL_ELSE>&nbsp;</TMPL_IF>
	</td>
	<td align="right" class="top" rowspan="2" width="1%">
	<table width="550" style="height: 72px; background-image: url(./images/std/bg.gif)" align="left" cellpadding=0 cellspacing=0>
    <tr><td align=right valign=bottom>
      <TMPL_IF server_time>
      <font color="#333300" size="2">		
      <TMPL_IF show_remaining_minutes>до начала тура осталось: <TMPL_VAR remaining_minutes> мин.<br></TMPL_IF>
      <TMPL_IF show_elapsed_minutes>с начала тура прошло: <span id="elapsed_minutes"><TMPL_VAR elapsed_minutes></span> мин.<br/></TMPL_IF>
      <TMPL_IF show_elapsed_days>с начала тура прошло: <TMPL_VAR elapsed_days> сут.<br></TMPL_IF>
      страница обновлена: <span id="server_time"><TMPL_VAR server_time></span></font>
      </TMPL_IF>
	</td></tr>
    </table>
    </td>
  </tr>
</table>
<table class="iface">
  <tr bgcolor="#7070ff" style="height: 30px">
	<td align="left">
    <span class="top">&nbsp;
    <TMPL_IF left_menu>
    [<TMPL_LOOP left_menu>
    <TMPL_IF selected><font color="#ffff00"><TMPL_VAR item ESCAPE=HTML></font>
    <TMPL_ELSE><a class="top" href="<TMPL_VAR href>"><TMPL_VAR item ESCAPE=HTML></a></TMPL_IF>
    <TMPL_UNLESS __last__>|</TMPL_UNLESS>
    </TMPL_LOOP>]
    </TMPL_IF></span>
    </td>
    <td align="right">
    <span class="top">
    [<TMPL_LOOP right_menu>
    <TMPL_IF selected><font color="#ffff00"><TMPL_VAR item ESCAPE=HTML></font>
    <TMPL_ELSE><a class="top" href="<TMPL_VAR href>"><TMPL_VAR item ESCAPE=HTML></a></TMPL_IF>
    <TMPL_UNLESS __last__>|</TMPL_UNLESS>
    </TMPL_LOOP>]&nbsp;
    </span>
    </td>
  </tr>
  <TMPL_IF submenu>
  <tr bgcolor="#bbbbff" style="height: 25px">
    <td colspan="2">&nbsp;
    <TMPL_LOOP submenu>
      <TMPL_IF selected>
      <span style="font-size: 12px"><TMPL_VAR item_name></span>
      <TMPL_ELSE>
      <a href="<TMPL_VAR href_item>" style="color:#3030a0; font-size:12px" <TMPL_IF item_target>target="<TMPL_VAR item_target>"</TMPL_IF>><TMPL_VAR item_name></a>
      </TMPL_IF>
      <TMPL_UNLESS "__last__">|</TMPL_UNLESS>	
	</TMPL_LOOP>
    </td>
  </tr>
  </TMPL_IF>
</table>
<div style="width: 99%; padding: 4px">