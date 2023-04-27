#!/bin/sh
CWD=$(pwd)
KERNEL_VAR_FILE=${CWD}/kernel-vars

if ! dpkg-architecture -iamd64; then
    echo "Openvpn-dco is only buildable on amd64 platforms"
    exit 0
fi

if [ ! -f ${KERNEL_VAR_FILE} ]; then
    echo "Kernel variable file '${KERNEL_VAR_FILE}' does not exist, run ./build_kernel.sh first"
    exit 1
fi

. ${KERNEL_VAR_FILE}

# 0.1 is required for openvpn 2.6.1
url="https://github.com/OpenVPN/ovpn-dco/archive/refs/tags/v0.1.20230206.tar.gz"

cd ${CWD}

DRIVER_NAME="ovpn-dco"
DRIVER_FILE="${DRIVER_NAME}-$(basename ${url} | sed -e s/tar_0/tar/)"
DRIVER_DIR="${DRIVER_FILE%.tar.gz}"
DRIVER_VERSION=$(echo ${DRIVER_DIR} | awk -F${DRIVER_NAME} '{print substr($2,3)}')
DRIVER_VERSION_EXTRA="-0"

# Build up Debian related variables required for packaging
DEBIAN_ARCH=$(dpkg --print-architecture)
DEBIAN_DIR="${CWD}/vyos-${DRIVER_NAME}_${DRIVER_VERSION}${DRIVER_VERSION_EXTRA}_${DEBIAN_ARCH}"
DEBIAN_CONTROL="${DEBIAN_DIR}/DEBIAN/control"
DEBIAN_POSTINST="${CWD}/vyos-${DRIVER_NAME}.postinst"

# Fetch Openvpn-dco archvie from github
if [ -e ${DRIVER_FILE} ]; then
    rm -f ${DRIVER_FILE}
fi
curl -L -o ${DRIVER_FILE} ${url}
if [ "$?" -ne "0" ]; then
    exit 1
fi

# Unpack archive
if [ -d ${DRIVER_DIR} ]; then
    rm -rf ${DRIVER_DIR}
fi
mkdir -p ${DRIVER_DIR}
tar --strip-components=1 -C ${DRIVER_DIR} -xf ${DRIVER_FILE}

cd ${DRIVER_DIR}
if [ -z $KERNEL_DIR ]; then
    echo "KERNEL_DIR not defined"
    exit 1
fi

echo "I: Compile Kernel module for ${DRIVER_NAME} driver"
make -j $(getconf _NPROCESSORS_ONLN) KERNEL_SRC="${KERNEL_DIR}" REVISION=${DRIVER_VERSION} all

if [ "x$?" != "x0" ]; then
    exit 1
fi

mkdir -p ${DEBIAN_DIR}/lib/modules/${KERNEL_VERSION}${KERNEL_SUFFIX}/updates/drivers/net/ovpn-dco
cp drivers/net/ovpn-dco/*.ko ${DEBIAN_DIR}/lib/modules/${KERNEL_VERSION}${KERNEL_SUFFIX}/updates/drivers/net/ovpn-dco/

if [ -f ${DEBIAN_DIR}.deb ]; then
    rm ${DEBIAN_DIR}.deb
fi

# build Debian package
echo "I: Building Debian package vyos-kmod-${DRIVER_NAME}"
cd ${CWD}

# delete non required files which are also present in the kernel package
# und thus lead to duplicated files
find ${DEBIAN_DIR} -name "modules.*" | xargs rm -f

echo "#!/bin/sh" > ${DEBIAN_POSTINST}
echo "/sbin/depmod -a ${KERNEL_VERSION}${KERNEL_SUFFIX}" >> ${DEBIAN_POSTINST}

fpm --input-type dir --output-type deb --name vyos-kmod-${DRIVER_NAME} \
    --version ${DRIVER_VERSION}${DRIVER_VERSION_EXTRA} --deb-compression gz \
    --maintainer "VyOS Package Maintainers <maintainers@vyos.net>" \
    --description "Kernel driver for ${DRIVER_NAME}" \
    --depends linux-image-${KERNEL_VERSION}${KERNEL_SUFFIX} \
    --license "GPL2" -C ${DEBIAN_DIR} --after-install ${DEBIAN_POSTINST}

echo "I: Cleanup ${DRIVER_NAME} source"
cd ${CWD}
if [ -e ${DRIVER_FILE} ]; then
    rm -f ${DRIVER_FILE}
fi
if [ -d ${DRIVER_DIR} ]; then
    rm -rf ${DRIVER_DIR}
fi
if [ -d ${DEBIAN_DIR} ]; then
    rm -rf ${DEBIAN_DIR}
fi
