<h2><TMPL_IF code>Задача <TMPL_VAR code>. </TMPL_IF><TMPL_VAR title ESCAPE=HTML></h2>
<TMPL_IF author>Автор: <TMPL_VAR author ESCAPE=HTML><br><br></TMPL_IF>
<table class="nobr">
<tr>
  <td width="1%">Входной файл:</td><td><TMPL_VAR input_file ESCAPE=HTML></td>
  <td>&nbsp;</td>
  <td width="1%">Ограничение времени на тест:</td><td><TMPL_VAR time_limit> сек</td></tr>
<tr>
  <td>Выходной файл:</td><td><TMPL_VAR output_file ESCAPE=HTML></td>
  <td>&nbsp;</td>
  <td>Ограничение памяти на тест:</td><td><TMPL_VAR memory_limit> Мб</td></tr>
  <TMPL_IF show_points><tr><td>Максимальная оценка:</td><td><TMPL_VAR max_points> баллов</td>
  <td colspan="3">&nbsp;</td></tr></TMPL_IF>
</table>
<TMPL_IF keywords>Ключевые слова: <TMPL_VAR keywords><br/><br/></TMPL_IF>
<TMPL_IF statement>
  <h3>Условие</h3>
  <TMPL_VAR statement>
</TMPL_IF>
<TMPL_IF explanation>
  <h3>Разбор</h3>
  <TMPL_VAR explanation>
<TMPL_ELSE>
<TMPL_IF input_format>
  <h3>Формат входного файла</h3>
  <TMPL_VAR input_format>
</TMPL_IF>
<TMPL_IF formal_input>
  <h3>Формальный вход</h3>
  <pre><TMPL_VAR formal_input></pre>
</TMPL_IF>
<TMPL_IF output_format>
  <h3>Формат выходного файла</h3>
  <TMPL_VAR output_format>
</TMPL_IF>    
<TMPL_IF pconstraints>
  <h3>Ограничения</h3>
  <TMPL_VAR pconstraints>
</TMPL_IF>
<TMPL_IF extended_samples>
<TMPL_LOOP samples>
<h4>Пример входного файла &#8470;<TMPL_VAR rank></h4>
<pre><code><TMPL_VAR in_file></code></pre>
<h4>Пример выходного файла &#8470;<TMPL_VAR rank></h4>
<pre><code><TMPL_VAR out_file></code></pre>
</TMPL_LOOP>
<TMPL_ELSE>
<h3>Примеры тестов</h3>
<table class="sample" id="sample<TMPL_VAR id>">
<tr><th>&#8470;</th><th>Входной файл</th><th>Выходной файл</th></tr>
<TMPL_LOOP samples>
<tr>
  <td><TMPL_VAR rank></td>
  <td><pre><code><TMPL_VAR in_file></code></pre></td>
  <td><pre><code><TMPL_VAR out_file></code></pre></td>
</tr>
</TMPL_LOOP>
</table>
</TMPL_IF>
</TMPL_IF>