#!/bin/sh

if [ "${RUNNER_OS}" = "Windows" ] ; then
	ext=".exe"
else
	ext=''
fi

ecabal() {
	cabal "$@"
}

sync_from() {
	if [ "${RUNNER_OS}" != "Windows" ] ; then
		cabal_store_path="$(dirname "$(cabal help user-config | tail -n 1 | xargs)")/store"
	fi

	cabal-cache sync-from-archive \
		--host-name-override=${S3_HOST} \
		--host-port-override=443 \
		--host-ssl-override=True \
		--region us-west-2 \
		$([ "${RUNNER_OS}" != "Windows" ] && echo --store-path="$cabal_store_path") \
		--archive-uri "s3://ghcup-hs/${RUNNER_OS}-${ARCH}-${DISTRO}"
}

sync_to() {
	if [ "${RUNNER_OS}" != "Windows" ] ; then
		cabal_store_path="$(dirname "$(cabal help user-config | tail -n 1 | xargs)")/store"
	fi

	cabal-cache sync-to-archive \
		--host-name-override=${S3_HOST} \
		--host-port-override=443 \
		--host-ssl-override=True \
		--region us-west-2 \
		$([ "${RUNNER_OS}" != "Windows" ] && echo --store-path="$cabal_store_path") \
		--archive-uri "s3://ghcup-hs/${RUNNER_OS}-${ARCH}-${DISTRO}"
}

raw_eghcup() {
	"$GHCUP_BIN/ghcup${ext}" -v -c "$@"
}

eghcup() {
	if [ "${OS}" = "Windows" ] ; then
		"$GHCUP_BIN/ghcup${ext}" -c -s "file:/$CI_PROJECT_DIR/data/metadata/ghcup-${JSON_VERSION}.yaml" "$@"
	else
		"$GHCUP_BIN/ghcup${ext}" -c -s "file://$CI_PROJECT_DIR/data/metadata/ghcup-${JSON_VERSION}.yaml" "$@"
	fi
}

sha_sum() {
	if [ "${OS}" = "FreeBSD" ] ; then
		sha256 "$@"
	else
		sha256sum "$@"
	fi

}

git_describe() {
	git config --global --get-all safe.directory | grep '^\*$' || git config --global --add safe.directory "*"
	git describe --always
}

download_cabal_cache() {
	(
	set -e
	dest="$HOME/.local/bin/cabal-cache"
    url=""
	exe=""
	cd /tmp
	case "${RUNNER_OS}" in
		"Linux")
			case "${DISTRO}" in
				"Alpine")
					case "${ARCH}" in
						"32") url=https://downloads.haskell.org/~ghcup/unofficial-bindists/cabal-cache/1.0.5.1/i386-linux-alpine-cabal-cache-1.0.5.1
							;;
						"64") url=https://downloads.haskell.org/~ghcup/unofficial-bindists/cabal-cache/1.0.5.1/x86_64-linux-alpine-cabal-cache-1.0.5.1
							;;
					esac
					;;
				*)
					case "${ARCH}" in
						"64") url=https://github.com/haskell-works/cabal-cache/releases/download/v1.0.5.1/cabal-cache-x86_64-linux.gz
							;;
						"ARM64") url=https://downloads.haskell.org/~ghcup/unofficial-bindists/cabal-cache/1.0.5.1/aarch64-linux-cabal-cache-1.0.5.1
							;;
						"ARM") url=https://downloads.haskell.org/~ghcup/unofficial-bindists/cabal-cache/1.0.5.1/armv7-linux-cabal-cache-1.0.5.1
							;;
					esac
					;;
			esac
			;;
		"FreeBSD")
			url=https://downloads.haskell.org/~ghcup/unofficial-bindists/cabal-cache/1.0.5.1/x86_64-freebsd-cabal-cache-1.0.5.1
			;;
		"Windows")
			exe=".exe"
			url=https://downloads.haskell.org/~ghcup/unofficial-bindists/cabal-cache/1.0.5.1/x86_64-mingw64-cabal-cache-1.0.5.1.exe
			;;
		"macOS")
			case "${ARCH}" in
				"ARM64") url=https://downloads.haskell.org/~ghcup/unofficial-bindists/cabal-cache/1.0.5.1/aarch64-apple-darwin-cabal-cache-1.0.5.1
					;;
				"64") url=https://downloads.haskell.org/~ghcup/unofficial-bindists/cabal-cache/1.0.5.1/x86_64-apple-darwin-cabal-cache-1.0.5.1
					;;
			esac
			;;
	esac

	if [ -n "${url}" ] ; then
		case "${url##*.}" in
			"gz")
				curl -L -o - "${url}" | gunzip > cabal-cache${exe}
				;;
			*)
				curl -o cabal-cache${exe} -L "${url}"
				;;
		esac
		chmod +x cabal-cache${exe}
		cp "cabal-cache${exe}" "${dest}${exe}"
	fi
    )
}

build_with_cache() {
	ecabal configure "$@"
	ecabal build --dependencies-only "$@" --dry-run
	sync_from
	ecabal build --dependencies-only "$@" || sync_to
	sync_to
	ecabal build "$@"
	sync_to
}

install_ghcup() {
	find "$GHCUP_INSTALL_BASE_PREFIX"
	mkdir -p "$GHCUP_BIN"
	mkdir -p "$GHCUP_BIN"/../cache

	if [ "${RUNNER_OS}" = "FreeBSD" ] ; then
		curl -o ghcup https://downloads.haskell.org/ghcup/tmp/x86_64-portbld-freebsd-ghcup-0.1.18.1
		chmod +x ghcup
		mv ghcup "$HOME/.local/bin/ghcup"
	else
		curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_MINIMAL=1 sh
	fi
}

strip_binary() {
	(
	set -e
	binary=$1
	if [ "${RUNNER_OS}" = "macOS" ] ; then
		strip "${binary}"
	else
		if [ "${RUNNER_OS}" != "Windows" ] ; then
			strip -s "${binary}"
		fi
	fi
	)
}