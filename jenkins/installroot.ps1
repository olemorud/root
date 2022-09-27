# POWERSHELL SCRIPT TO INSTALL ROOT ON WINDOWS

Where-Object . # crashes before git clone if run on non-windows OS

git clone --branch latest-stable --depth=1 https://github.com/root-project/root.git source
mkdir .\build\
mkdir .\install\

cd .\build\
cmake -G"Visual Studio 16 2019" -A x64 -Thost=x64 -DCMAKE_INSTALL_PREFIX=..\build\ ..\source\

cmake --build . --config $OPTIONS --target install
