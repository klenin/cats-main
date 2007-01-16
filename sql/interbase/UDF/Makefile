# ---------------------------------------------------------------------
# CHANGE this definition to point to your InterBase installation directory
# ---------------------------------------------------------------------
IBASE=		/usr/local/firebird


# ---------------------------------------------------------------------
# General Compiler and linker Defines for Linux
# ---------------------------------------------------------------------
CC=		gcc
LINK=		gcc
LIB_LINK=	ld
CFLAGS=		-c -w -I$(IBASE)/include  
LIB_CFLAGS=	-fPIC $(CFLAGS)
LINK_FLAGS=	-lfbclient -ldl -lcrypt 
LIB_LINK_FLAGS=	-shared -lfbclient
RM=		rm -f

.SUFFIXES: .o .c

.c.o:
	$(CC) $< $(CFLAGS) 

all:	cats_udf_lib

cats_udf_lib.o:	cats_udf_lib.c

cats_udf_lib: cats_udf_lib.o
	$(LIB_LINK) $@.o -o $@ $(LIB_LINK_FLAGS)
	@echo ------------------------------------------------------
	@echo You need to copy cats_udf_lib to the interbase lib directory
	@echo in order for the server to load it. 
	@echo ------------------------------------------------------

clean:
	rm *.o
