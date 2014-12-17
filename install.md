# Environment
 * Windows XP or newer
 * Microsoft Visual C++ compiler
 * wget

# Apache 2.2
 * https://www.apachelounge.com/download/win32/binaries/httpd-2.2.29-win32-VC9.zip

${APACHE_PATH} -- default is `C:\Apache2`

# Perl
 * http://strawberryperl.com/download/5.16.3.1/strawberry-perl-5.16.3.1-32bit.msi 

${PERL_PATH} -- default is `C:\Strawberry`

# Apache's mod_perl
 * http://people.apache.org/~stevehay/mod_perl-2.0.8-strawberryperl-5.16.3.1-32bit.zip

Merge corresponding directories from archive with ${APACHE_PATH} and ${PERL_PATH} directories respectively.
(In case of using Active perl -- check corresponding archive here http://people.apache.org/~stevehay/ )

# Firebird 2.1
 * http://sourceforge.net/projects/firebird/files/firebird-win32/2.1.7-Release/Firebird-2.1.7.18553_0_Win32.exe/download
 
${FIREBIRD_PATH} -- default is `"C:\Program Files\Firebird\Firebird_2_1"`

# Aspell installation (not fully functional!)
 * http://ftp.gnu.org/gnu/aspell/w32/Aspell-0-50-3-3-Setup.exe
 * http://ftp.gnu.org/gnu/aspell/w32/Aspell-en-0.50-2-3.exe
 * http://ftp.gnu.org/gnu/aspell/w32/Aspell-ru-0.50-2-3.exe
 * http://ftp.gnu.org/gnu/aspell/w32/aspell-dev-0-50-3-3.zip

aspell_path -- default is `C:\Aspell` or `"C:\Program Files\Aspell"`

Add `${ASPELL_PATH}\bin` to PATH
Copy contents of dev archive to corresponding `${PERL_PATH}\c\include` and `${PERL_PATH}\c\lib` (Note delete version number from library files -- eg rename aspell**~~-15~~**.lib to **aspell.lib**)

**!!! Problem with dictionaries - perl cannot find en_US dictionary !!!**

#Perl modules
```
cpanm DBI Algorithm::Diff SQL::Abstract JSON::XS YAML::Syck Apache2::Request XML::Parser::Expat Template
# now open cpan console
cpan
# in cpan console query the next commands
force install Text::Aspell 
force install Archive::Zip
force install DBD::Firebird
```
#Apache config 
Add to httpd.conf
```
LoadModule perl_module modules/mod_perl.so
LoadModule apreq_module modules/mod_apreq2.so
```
Uncomment in httpd.conf module `#LoadModule expires_module module/mod_expires.so`
```
LoadModule expires_module module/mod_expires.so
```