FLASCC:=X
FLEX:=X
AS3COMPILER:=asc2.jar

# Detect host
$?UNAME=$(shell uname -s)
ifneq (,$(findstring CYGWIN,$(UNAME)))
	$?nativepath=$(shell cygpath -at mixed "$(1)")
	$?unixpath=$(shell cygpath -at unix "$(1)")
else
	$?nativepath=$(abspath $(1))
	$?unixpath=$(abspath $(1))
endif

# CrossBridge SDK Home
$?FLASCC:=$(call unixpath,$(FLASCC_ROOT)/sdk)
# $?ASC2=java -jar $(call nativepath,$(FLASCC)/usr/lib/asc2.jar) -merge -md -parallel
$?ASC2="$(call nativepath,$(FLASCC)/usr/lib/asc2.jar)"

# Auto Detect AIR/Flex SDKs
$?FLEX=$(AIR_HOME)

ifeq (,$(FLEX))
	$?FLEX:=X
endif

compile: check
	@mkdir -p install/usr/lib
	@mkdir -p install/usr/include

	@echo "Compiling libGL.as"
	java -jar $(ASC2) -merge -md -parallel -strict -optimize -abcfuture -AS3 \
	-import $(call nativepath,$(FLASCC)/usr/lib/builtin.abc) \
	-import $(call nativepath,$(FLASCC)/usr/lib/playerglobal.abc) \
	-import $(call nativepath,$(FLASCC)/usr/lib/BinaryData.abc) \
	-import $(call nativepath,$(FLASCC)/usr/lib/C_Run.abc) \
	-import $(call nativepath,$(FLASCC)/usr/lib/CModule.abc) \
	-in src/com/adobe/utils/v3/AGALMiniAssembler.as \
	libGL.as
	@mv libGL.abc install/usr/lib/

	# -in src/com/adobe/utils/extended/AGALMiniAssembler.as \
	# -in src/com/adobe/utils/AGALMiniAssembler.as \
	# -in src/com/adobe/utils/AGALMacroAssembler.as \
	# -in src/com/adobe/utils/FractalGeometryGenerator.as \
	# -in src/com/adobe/utils/PerspectiveMatrix3D.as \
	# -in src/com/adobe/utils/macro/AGALPreAssembler.as \
	# -in src/com/adobe/utils/macro/AGALVar.as \
	# -in src/com/adobe/utils/macro/Expression.as \
	# -in src/com/adobe/utils/macro/BinaryExpression.as \
	# -in src/com/adobe/utils/macro/ExpressionParser.as \
	# -in src/com/adobe/utils/macro/NumberExpression.as \
	# -in src/com/adobe/utils/macro/UnaryExpression.as \
	# -in src/com/adobe/utils/macro/VariableExpression.as \
	# -in src/com/adobe/utils/macro/VM.as \
	@mv libGL.abc install/usr/lib/

	@echo "Compiling libGL.cpp"
	@$(FLASCC)/usr/bin/g++ -fno-exceptions -O4 -c -Iinstall/usr/include/ libGL.cpp
	@$(FLASCC)/usr/bin/ar crus install/usr/lib/libGL.a install/usr/lib/libGL.abc libGL.o
	@echo "Compiling mipmap.c quad.c"
	@$(FLASCC)/usr/bin/gcc -fno-exceptions -O4 -c -Iinstall/usr/include/ -Linstall/usr/lib mipmap.c
	@$(FLASCC)/usr/bin/gcc -fno-exceptions -O4 -c -Iinstall/usr/include/ -Linstall/usr/lib quad.c
	@$(FLASCC)/usr/bin/ar crus install/usr/lib/libGLU.a mipmap.o quad.o

	@rm -f libGL.o
	@rm -f mipmap.o
	@rm -f quad.o

check:
	@if [ -d $(FLASCC)/usr/bin ] ; then true ; \
	else echo "Couldn't locate FLASCC sdk directory, please invoke make with \"make FLASCC=/path/to/FLASCC/sdk ...\"" ; exit 1 ; \
	fi

	# @if [ -d "$(FLEX)/bin" ] ; then true ; \
	# else echo "Couldn't locate Flex sdk directory, please invoke make with \"make FLEX=/path/to/flex  ...\"" ; exit 1 ; \
	# fi

install: check
	@cp -rf install/usr/include/ $(FLASCC)/usr/include
	@cp -rf install/usr/lib/* $(FLASCC)/usr/lib
	# @cp $(FLASCC)/usr/SDL_opengl.h $(FLASCC)/usr/include/SDL/

all: compile install


