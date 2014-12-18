# Environment
 * Windows XP or newer
 * Microsoft Visual C++ compiler
 * GnuWin32 utils -- bsdtar, unzip, sed, rm, cp

# Apache 2.2
 * https://www.apachelounge.com/download/win32/binaries/httpd-2.2.29-win32-VC9.zip

${APACHE_PATH} -- default is `C:\Apache2`

# Perl
 * http://strawberryperl.com/download/5.16.3.1/strawberry-perl-5.16.3.1-32bit.msi 
 * or http://strawberryperl.com/download/5.16.3.1/strawberry-perl-5.16.3.1-32bit.zip

If installing from zip -- don't forget to run bat files in root directory after unpacking

${PERL_PATH} -- default is `C:\Strawberry`

# Firebird >=2.1
 * http://sourceforge.net/projects/firebird/files/firebird-win32/2.1.7-Release/Firebird-2.1.7.18553_0_Win32.exe/download
 
${FIREBIRD_PATH} -- default is `"C:\Program Files\Firebird\Firebird_2_1"`

# Aspell installation (not fully functional!)
 * http://ftp.gnu.org/gnu/aspell/w32/Aspell-0-50-3-3-Setup.exe
 * http://ftp.gnu.org/gnu/aspell/w32/Aspell-en-0.50-2-3.exe
 * http://ftp.gnu.org/gnu/aspell/w32/Aspell-ru-0.50-2-3.exe

aspell_path -- default is `C:\Aspell` or `"C:\Program Files\Aspell"`

Add `${ASPELL_PATH}\bin` to PATH

**!!! Problem with dictionaries - perl cannot find en_US dictionary !!!**

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
Uncomment in httpd.conf vhosts config file `#Include conf/extra/httpd-vhosts.conf`
```
Include conf/extra/httpd-vhosts.conf
```

#Automatic script
Run deploy.bat and follow instructions