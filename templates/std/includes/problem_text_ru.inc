<h2>
<TMPL_IF code>Задача <TMPL_VAR code>.</TMPL_IF>
<TMPL_VAR problem_name ESCAPE=HTML>
</h2>
Автор задачи: <TMPL_VAR author ESCAPE=HTML><br><br>
<table>
<tr><td>Входной файл:</td><td><TMPL_VAR input_file ESCAPE=HTML></td></tr>
<tr><td>Выходной файл:</td><td><TMPL_VAR output_file ESCAPE=HTML></td></tr>
<tr><td>Ограничение времени на тест:</td><td><TMPL_VAR time_limit> сек</td></tr>
<tr><td>Ограничение памяти на тест:</td><td><TMPL_VAR memory_limit> Мб</td></tr>
</table>

<TMPL_IF statement>
    <h3><i>Условие</i></h3>
    <TMPL_VAR statement>
</TMPL_IF>

<TMPL_IF constraints>
    <h3><i>Ограничения</i></h3>
    <TMPL_VAR constraints>
</TMPL_IF>

<TMPL_IF input_format>
    <h3><i>Формат входного файла</i></h3>
    <TMPL_VAR input_format>
</TMPL_IF>

<TMPL_IF output_format>
    <h3><i>Формат выходного файла</i></h3>
    <TMPL_VAR output_format>
</TMPL_IF>    

<TMPL_LOOP samples>
<h4><i>Пример входного файла &#8470;<TMPL_VAR rank></i></h4>
<pre><code><TMPL_VAR test_in></code></pre>
<h4><i>Пример выходного файла &#8470;<TMPL_VAR rank></i></h4>
<pre><code><TMPL_VAR test_out></code></pre>
</TMPL_LOOP>