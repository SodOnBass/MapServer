#!/bin/sh
set -eu

export CC="ccache gcc"
export CXX="ccache g++"

echo "Versions"
php -v
which python

if [ "${WITH_ASAN:-}" = "true" ]; then
    # -DNDEBUG to avoid issues with cairo cleanup
    make cmakebuild MFLAGS="-j2" CMAKE_C_FLAGS="-g -fsanitize=address -DNDEBUG" CMAKE_CXX_FLAGS="-g -fsanitize=address -DNDEBUG" \
    EXTRA_CMAKEFLAGS="-DCMAKE_BUILD_TYPE=None -DCMAKE_EXE_LINKER_FLAGS=-fsanitize=address"
else
    if [ "${MAPSCRIPT_PYTHON:-}" = "true" ]; then
        # only build MapServer with the Python MapScript
        make cmakebuild_mapscript_python MFLAGS="-j2" CMAKE_C_FLAGS="-O2" CMAKE_CXX_FLAGS="-O2" LIBMAPSERVER_EXTRA_FLAGS="-Wall -Werror -Wextra"
    else
        make cmakebuild MFLAGS="-j2" CMAKE_C_FLAGS="-O2" CMAKE_CXX_FLAGS="-O2" LIBMAPSERVER_EXTRA_FLAGS="-Wall -Werror -Wextra"
    fi
fi

if [ "${MAPSCRIPT_PYTHON:-}" = "true" ]; then
    ci/mapscript_python.sh
fi

if [ "${MAPSCRIPT_PHP:-}" = "true" ]; then
    ci/mapscript_php.sh
fi

if [ "${RUN_MSAUTOTESTS:-}" = "true" ]; then
    sudo sed -i  's/md5/trust/' /etc/postgresql/12/main/pg_hba.conf
    sudo sed -i  's/peer/trust/' /etc/postgresql/12/main/pg_hba.conf
    sudo service postgresql restart 12

    cd msautotest
    ./create_postgis_test_data.sh
    # copy custom projection to the PROJ_DATA folder
    sudo cp ./wxs/data/epsg2 /usr/share/proj/
    cd ..

    if [ "${WITH_ASAN:-}" = "true" ]; then
        export AUTOTEST_OPTS="--strict --run_under_asan"
        # Only run tests that only involve mapserv/map2img binaries. mspython, etc would require LD_PREOLOAD'ing the asan shared object
        make -j4 asan_compatible_tests
    else
        make -j4 test
    fi
fi

if [ "${RUN_COVERALLS:-}" = "true" ]; then
    ln -s ../../../src/mapparser.y build/CMakeFiles/mapserver.dir/
    ln -s ../../../src/maplexer.l build/CMakeFiles/mapserver.dir/
    coveralls --exclude renderers --exclude mapscript --exclude apache --exclude build/mapscript/mapscriptJAVA_wrap.c \
    --exclude build/mapscript/mapscriptPYTHON_wrap.c --exclude map2img.c --exclude legend.c --exclude scalebar.c \
    --exclude msencrypt.c --exclude sortshp.c --exclude shptreevis.c --exclude shptree.c --exclude testexpr.c \
    --exclude testcopy.c --exclude shptreetst.c --exclude tile4ms.c --extension .c --extension .cpp
fi

