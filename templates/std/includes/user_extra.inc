<table class="registration">
<tr><td>Страна</td><td>
    <select name="country">
    <TMPL_LOOP NAME=countries>
    <option value="<TMPL_VAR id>" <TMPL_IF selected>selected="selected"</TMPL_IF>><TMPL_VAR name ESCAPE=HTML></option>
    </TMPL_LOOP>
    </select>
</td></tr>
<tr><td>Город / регион</td><td> <input type=text name="city" size="50" value="<TMPL_VAR city ESCAPE=HTML>" class="bordered"></td></tr>
<tr><td>Девиз команды</td><td> <input type=text name='motto' size=50 value='<TMPL_VAR motto ESCAPE=HTML>' class=bordered></td></tr>
<tr><td>ФИО капитана команды</td><td> <input type=text name='capitan_name' size=50 value='<TMPL_VAR capitan_name ESCAPE=HTML>' class=bordered></td></tr>
<tr><td>E-Mail</td><td> <input type=text name='email' size=50 value='<TMPL_VAR email ESCAPE=HTML>' class=bordered></td></tr>
<tr><td>ICQ</td><td> <input type=text name='icq_number' size=50 value='<TMPL_VAR icq_number ESCAPE=HTML>' class=bordered></td></tr>
<tr><td>Адрес домашней страницы</td><td> <input type=text name='home_page' size=50 value='<TMPL_VAR home_page ESCAPE=HTML>' class=bordered></td></tr>
</table>
