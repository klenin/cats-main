<h2>
<TMPL_IF code>Problem <TMPL_VAR code>.</TMPL_IF>
<TMPL_VAR title ESCAPE=HTML>
</h2>
Author: <TMPL_VAR author ESCAPE=HTML><br><br>

<table>
<tr><td>Input file:</td><td><TMPL_VAR input_file ESCAPE=HTML></td></tr>
<tr><td>Output file:</td><td><TMPL_VAR output_file ESCAPE=HTML></td></tr>
<tr><td>Time limit:</td><td><TMPL_VAR time_limit> sec</td></tr>
<tr><td>Memory limit:</td><td><TMPL_VAR memory_limit> Mb</td></tr>
</table>

<TMPL_IF statement>
    <h3><i>Statement</i></h3>
    <TMPL_VAR statement>
</TMPL_IF>

<TMPL_IF input_format>
    <h3><i>Input file format</i></h3>
    <TMPL_VAR input_format>
</TMPL_IF>

<TMPL_IF output_format>
    <h3><i>Output file format</i></h3>
    <TMPL_VAR output_format>
</TMPL_IF>

<TMPL_IF pconstraints>
    <h3><i>Constraints</i></h3>
    <TMPL_VAR pconstraints>
</TMPL_IF>

<TMPL_IF extended_samples>
<TMPL_LOOP samples>
<h4><i>Sample input #<TMPL_VAR rank></i></h4>
<pre><code><TMPL_VAR in_file></code></pre>
<h4><i>Sample output #<TMPL_VAR rank></i></h4>
<pre><code><TMPL_VAR out_file></code></pre>
</TMPL_LOOP>
<TMPL_ELSE>
<h3><i>Sample tests</i></h4>
<table class="sample">
<tr><th>No.</th><th>Sample input</th><th>Sample output</th></tr>
<TMPL_LOOP samples>
<tr>
  <td><TMPL_VAR rank></td>
  <td><pre><code><TMPL_VAR in_file></code></pre></td>
  <td><pre><code><TMPL_VAR out_file></code></pre></td>
</tr>
</TMPL_LOOP>
</table>
</TMPL_IF>