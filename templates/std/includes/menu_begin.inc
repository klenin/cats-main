<html><head>
<title>CATS - <TMPL_VAR contest_title ESCAPE=HTML></title>
<meta name="Content-Type" content="text/html; charset=utf-8">
<TMPL_IF refresh>
<meta http-equiv="Refresh" CONTENT="<TMPL_VAR refresh>">    
</TMPL_IF>
<link rel="stylesheet" type="text/css" href="./docs/std/main.css">
</head>
<body leftmargin=0 topmargin=0>
<table width=100% cellspacing=0 cellpadding=0>
    <tr bgcolor=#ffcc55 height=69 valign=bottom>
	<td class='top' rowspan=2>
	    <img src="./images/std/logo.gif" border=0>
	</td>
	<td valign=bottom width=100% align=left>
	    <TMPL_IF contest_title><font size=5 color=#333300><TMPL_VAR contest_title>
	    </font></TMPL_IF>

	</td>
	<td align=right class='top' rowspan=2>	
	<table width=550 height=72 align=left cellpadding=0 cellspacing=0 background="./images/std/bg.gif">
	    <tr>
		<td align=right valign=bottom>
		<TMPL_IF server_time>
		<font color=#333300 size=2>		
		<TMPL_IF show_remaining_minutes>до начала тура осталось: <TMPL_VAR remaining_minutes> (мин.)<br></TMPL_IF>
		<TMPL_IF show_elapsed_minutes>с начала тура прошло: <TMPL_VAR elapsed_minutes> (мин.)<br></TMPL_IF>
		<TMPL_IF show_elapsed_days>с начала тура прошло: <TMPL_VAR elapsed_days> (сут.)<br></TMPL_IF>
		страница обновлена: <span id=server_time><TMPL_VAR server_time></span></font>
		</TMPL_IF>
		</td>
	    </tr>
    	</table>
	</td>
    </tr>
    <tr bgcolor=#ffcc55 height=3>
	<td>
	</td>
    </tr>
    <tr bgcolor=#7070ff class=bordered height=30>
	<td colspan=3>
	    <table width=100% cellpadding=0>
	    <tr>
	    <td align=left> 
	    <span class=top>
	    <TMPL_IF left_menu>
	    [
	    <TMPL_LOOP left_menu>
	    <TMPL_IF selected>
	    <font color=#ffff00><TMPL_VAR item ESCAPE=HTML></font>
	    <TMPL_ELSE> 
	    <a class=top href='<TMPL_VAR href>'><TMPL_VAR item ESCAPE=HTML></a>
	    </TMPL_IF>
	    <TMPL_UNLESS "__last__">|</TMPL_UNLESS>
	    </TMPL_LOOP>
	    ]
	    <TMPL_ELSE>&nbsp;</TMPL_IF></span>
	    </td>
	    <td align=right>
	    <span class=top>
	    <TMPL_LOOP right_menu>
	    <TMPL_IF selected>
	    <font color=#ffff00><TMPL_VAR item ESCAPE=HTML></font>
	    <TMPL_ELSE> 
	    <a class=top href='<TMPL_VAR href>'><TMPL_VAR item ESCAPE=HTML></a>
	    </TMPL_IF>
	    <TMPL_UNLESS "__last__">|</TMPL_UNLESS>
	    </TMPL_LOOP>
	    </span>
	    </td>
	    </tr>
	</table>
	</td>
    </tr>
    <TMPL_IF submenu>
        <tr bgcolor=#bbbbff height=25>
    	    <td colspan=3>&nbsp;
    	    <TMPL_LOOP submenu>
	    	<a href='<TMPL_VAR href_item>' style='color:#3030a0; font-size:12px' <TMPL_IF item_target>target='<TMPL_VAR item_target>'</TMPL_IF>><TMPL_VAR item_name></a>
	        <TMPL_UNLESS "__last__">|</TMPL_UNLESS>	
		</TMPL_LOOP>
	    </td>
	</tr>
    </TMPL_IF>
    <tr bgcolor=#ffffff valign=top>
	<td colspan=3>
	<table width=98% align=center height=100%>
	    <tr>
	    <td>
	    <br>