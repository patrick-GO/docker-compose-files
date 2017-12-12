#! /bin/bash
# Generating
#  * crypto-config
#  * channel-artifacts
#    * orderer.genesis.block
#    * channel.tx
#    * Org1MSPanchors.tx
#    * Org2MSPanchors.tx


[ $# -ne 1 ] && echo_b "Need config path as param" && exit 1
MODE=$1


# Run cmd inside the container
con_exec() {
	docker exec -it $GEN_CONTAINER "$@"
}

if [ -f ./func.sh ]; then
 source ./func.sh
elif [ -f scripts/func.sh ]; then
 source scripts/func.sh
fi

echo_b "Generating artifacts for ${MODE}"

echo_b "Clean existing container $GEN_CONTAINER"
[ "$(docker ps -a | grep $GEN_CONTAINER)" ] && docker rm -f $GEN_CONTAINER

pushd ${MODE}

echo_b "Check whether channel-artifacts or crypto-config exist already"
GEN_CRYPTO=true
if [ -d ${CRYPTO_CONFIG} ]; then #already exist, no need to re-gen crypto
  echo_b "${CRYPTO_CONFIG} existed, won't regenerate it."
  GEN_CRYPTO=false
else
	mkdir ${CRYPTO_CONFIG}
fi

GEN_ARTIFACTS=true
if [ ! -d ${CHANNEL_ARTIFACTS} ]; then
	echo_b "${CHANNEL_ARTIFACTS} not exists, create it."
	mkdir ${CHANNEL_ARTIFACTS}
fi

echo_b "Starting container $GEN_CONTAINER in background"
docker run \
	-d -it \
	--name $GEN_CONTAINER \
	-e "CONFIGTX_LOGGING_LEVEL=DEBUG" \
	-e "CONFIGTX_LOGGING_FORMAT=%{color}[%{id:03x} %{time:01-02 15:04:05.00 MST}] [%{longpkg}] %{callpath} -> %{level:.4s}%{color:reset} %{message}" \
	-v $PWD/configtx.yaml:${FABRIC_CFG_PATH}/configtx.yaml \
	-v $PWD/crypto-config.yaml:${FABRIC_CFG_PATH}/crypto-config.yaml \
	-v $PWD/${CRYPTO_CONFIG}:${FABRIC_CFG_PATH}/${CRYPTO_CONFIG} \
	-v $PWD/${CHANNEL_ARTIFACTS}:/tmp/${CHANNEL_ARTIFACTS} \
	${GEN_IMG} bash -c 'while true; do sleep 20171001; done'

if [ "${GEN_CRYPTO}" = "true" ]; then
	echo_b "Generating crypto-config"
	con_exec cryptogen generate --config=$FABRIC_CFG_PATH/crypto-config.yaml --output ${FABRIC_CFG_PATH}/${CRYPTO_CONFIG}
fi

if [ "${GEN_ARTIFACTS}" = "true" ]; then
	echo_b "Generate genesis block for system channel using configtx.yaml"
	[ -f ${CHANNEL_ARTIFACTS}/${ORDERER_GENESIS} ] || con_exec configtxgen -profile ${ORDERER_PROFILE} -outputBlock /tmp/${CHANNEL_ARTIFACTS}/${ORDERER_GENESIS}

	echo_b "Create the new app channel tx using configtx.yaml"
	[ -f ${CHANNEL_ARTIFACTS}/${APP_CHANNEL_TX} ] || con_exec configtxgen -profile TwoOrgsChannel -outputCreateChannelTx /tmp/$CHANNEL_ARTIFACTS/${APP_CHANNEL_TX} -channelID ${APP_CHANNEL}

	echo_b "Create the anchor peer configuration tx using configtx.yaml"
	[ -f ${CHANNEL_ARTIFACTS}/${UPDATE_ANCHOR_ORG1_TX} ] || con_exec configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate /tmp/${CHANNEL_ARTIFACTS}/${UPDATE_ANCHOR_ORG1_TX} -channelID ${APP_CHANNEL} -asOrg Org1MSP
	[ -f ${CHANNEL_ARTIFACTS}/${UPDATE_ANCHOR_ORG2_TX} ] || con_exec configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate /tmp/${CHANNEL_ARTIFACTS}/${UPDATE_ANCHOR_ORG2_TX} -channelID ${APP_CHANNEL} -asOrg Org2MSP
fi

echo_b "Remove the container $GEN_CONTAINER" && docker rm -f $GEN_CONTAINER

echo_g "Generated artifacts for ${MODE}"

