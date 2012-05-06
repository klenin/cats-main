</div>
<table class="iface">
<tr bgcolor="#7070ff" style="height: 30px" class="top">
  <td class="signed">
    текущий пользователь: 
    <TMPL_IF current_team_name><TMPL_VAR current_team_name ESCAPE=HTML>
    <TMPL_ELSE>анонимный</TMPL_IF>
  </td>
  <td align="right">
    <a href="https://github.com/klenin/cats-main/issues" class="signed">issues</a> |
    <a href="docs/" class="signed">документация</a> |
    <a href="<TMPL_VAR url_authors>" class="signed">&copy; 2002-2012 Авторы</a>&nbsp;
  </td>
</tr>
<tr bgcolor="#ffcc55" style="height: 40px">
  <td style="background-image: url(./images/std/bg2.gif)" class="down">
    &nbsp;<TMPL_INCLUDE 'timing.inc'>
  </td>
  <td align="right">
    <a href="http://imcs.dvgu.ru/works" class="signed2"> Кафедра информатики &nbsp;</a><br>
    <a href="http://dvfu.ru" class="signed2"> Дальневосточный федеральный университет &nbsp;</a>
  </td>
</tr>
</table>
</body>
</html>
