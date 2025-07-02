#!/bin/bash
#######################################################################
# Script Name: openvpn3-client.sh
# Description: script para conexão VPN openvpn cloud usando openvpn3
# Author: https://github.com/jeanrafaellourenco
# Date: 14/06/2021
# Dependencies: apt-transport-https, openvpn3
# Encode: UTF8
# Ref: https://openvpn.net/cloud-docs/openvpn-3-client-for-linux/
#######################################################################

_help() {
	cat <<EOF
Use: ${0##*/} [opção]
Opções:
     --instalar		- Se esse for o primeiro uso desse script
     --conectar   	- Para se conectar a VPN
     --status		- Verifica se está conectado a VPN
     --desconectar - Para se desconectar da VPN
[*]  Não execute com 'sudo' ou como 'root'.
[**] Use este script apenas em sistemas APT-based.
EOF
	exit 0
}

[[ $(id -u) -eq 0 ]] && _help | tail -n 2 | sed -n 1p && exit 1
[[ -z "$1" ]] && _help
[[ ! $(which apt) ]] && _help | tail -n 1 && exit 1

function instalar() {
    # Atualiza o sistema
    sudo apt update && sudo apt upgrade -y
    sudo apt dist-upgrade -y
    sudo apt install update-manager-core -y

    # Verifica se já existe um arquivo .ovpn
    OVPN_FILE=$(find ~ -maxdepth 1 -name "*.ovpn" | head -n 1)
    if [[ -z "$OVPN_FILE" ]]; then
        echo -e "❌ Nenhum arquivo .ovpn encontrado em: $HOME"
        exit 1
    fi

    # Verifica se openvpn3 já está instalado
    if command -v openvpn3 >/dev/null; then
        echo -e "✅ Programa 'openvpn3' já está instalado!\n"
        _help
        return
    fi

    # Detecta a versão da distribuição (ex: jammy, focal, etc.)
    DISTRO=$(/usr/bin/lsb_release -c | awk '{ print $2 }')

    # Adiciona o repositório oficial OpenVPN 3
    sudo apt install -y apt-transport-https curl gnupg
    curl -fsSL https://packages.openvpn.net/packages-repo.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/openvpn.gpg

    echo "deb [signed-by=/etc/apt/keyrings/openvpn.gpg] https://packages.openvpn.net/openvpn3/debian $DISTRO main" | \
        sudo tee /etc/apt/sources.list.d/openvpn-packages.list > /dev/null

    sudo apt update

    # Instala o OpenVPN 3
    sudo apt install -y openvpn3

    # Importa o arquivo .ovpn encontrado
    echo "Importando arquivo .ovpn: $OVPN_FILE"
    openvpn3 config-import --persistent --config "$OVPN_FILE"
}

function status() {
	openvpn3 sessions-list
}

function conectar() {
    echo "🔧 Limpando domínios DNS das interfaces de rede..."

    # Remove domínio DNS de interfaces de rede (corrige problemas com OpenVPN Cloud)
    ip -br link | awk '{print $1}' | grep -E -i "^(wl|en|et)" | while read -r iface; do
        sudo resolvectl domain "$iface" ""
    done

    # Verifica se já existe uma conexão ativa
    if pidof openvpn3-service-client > /dev/null; then
        echo -e "\n⚠️ Já existe uma conexão ativa. Desconecte antes de tentar novamente."
        _help
        return
    fi

	# Procurar um único arquivo .ovpn na pasta home
	OVPN_FILE=$(find ~ -maxdepth 1 -iname "*.ovpn" | head -n 1)

	# Validar se encontrou algum arquivo
	if [[ -z "$OVPN_FILE" ]]; then
		echo "❌ Nenhum arquivo .ovpn encontrado em $HOME"
		exit 1
	fi

	# Verificar se já foi importado
	CONFIG_EXISTE=$(openvpn3 configs-list | grep -F "$OVPN_FILE")

	if [[ -n "$CONFIG_EXISTE" ]]; then
		echo "✅ Configuração já foi importada anteriormente."
	else
		echo "📥 Importando configuração: $OVPN_FILE"
		openvpn3 config-import --persistent --config "$OVPN_FILE"
	fi

    # Captura o primeiro profile de configuração disponível
    CONFIG_PATH=$(openvpn3 configs-list --json | jq -r 'keys[0]')

    if [[ -z "$CONFIG_PATH" ]]; then
        echo "❌ Nenhuma configuração encontrada. Importe primeiro com:"
        echo "   openvpn3 config-import --config caminho.ovpn"
        return 1
    fi

    echo "📡 Iniciando sessão VPN com o perfil: $CONFIG_PATH"
    openvpn3 session-start --config-path "$CONFIG_PATH"

    echo -e "\n⏳ Aguardando conexão... Pode levar alguns segundos."
    sleep 10

    echo -e "✅ Se não houver erros, a conexão deve estar ativa."
    echo -e "ℹ️ Para verificar, use: openvpn3 sessions-list"
}

function desconectar() {
	[[ ! $(pidof openvpn3-service-client) ]] && echo -e "Nenhuma conexão foi encontrada!" && exit 1
	sudo pkill -9 openvpn
	echo -e "Aguarde..."
	sleep 5
	echo -e "\nDesconectado!"
	status
}

while [[ "$1" ]]; do
	case "$1" in
	--instalar) instalar ;;
	--conectar) conectar ;;
	--status) status ;;
	--desconectar) desconectar ;;
	*) echo -e "Opção inválida\n" && _help ;;
	esac
	shift
done
