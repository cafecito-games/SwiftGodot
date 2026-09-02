ODOCS=../SwiftGodotDocs/docs

all:
	echo Targets:
	echo    - build-docs: Builds the documentation
	echo    - preview-docs: Start local web server serving the documentation
	echo    - push-docs: Pushes the existing documentation, requires SwiftGodotDocs peer checked out
	echo    - release: Builds an xcframework package, documentation and pushes documentation
	echo    - package-godot-addon: Packages SwiftGodot as a binary-only Godot addon

build-docs:
	GENERATE_DOCS=1 DOCC_HTML_DIR=/Users/miguel/cvs/swift-docc-render-artifact/dist swift package \
		--allow-writing-to-directory $(ODOCS) \
		generate-documentation \
		--target SwiftGodot \
		--disable-indexing \
		--transform-for-static-hosting \
		--hosting-base-path /SwiftGodotDocs \
		--source-service github \
		--source-service-base-url https://github.com/migueldeicaza/SwiftGodot/blob/main \
		--checkout-path . \
		--emit-digest \
		--output-path $(ODOCS) \
		--verbose \
		>& build-docs.log

preview-docs:
	GENERATE_DOCS=1 swift package --disable-sandbox preview-documentation --target SwiftGodot --disable-indexing --emit-digest

release: check-args build-release build-docs push-docs

build-release: check-args
	sh -x scripts/release $(VERSION) $(NOTES) `git rev-parse HEAD`

package-godot-addon:
	@tag="$${TAG:-$${VERSION:-}}"; \
	if test -z "$$tag"; then echo "Set TAG=vX.Y.Z or VERSION=vX.Y.Z"; exit 1; fi; \
	xcframework="$${XCFRAMEWORK:-$${SWIFT_GODOT_XCFRAMEWORK:-.build/release-verify/SwiftGodot.xcframework}}"; \
	embed_xcframework="$${EMBED_XCFRAMEWORK:-$${SWIFT_GODOT_EMBED_XCFRAMEWORK:-.build/release-verify/SwiftGodotEmbed.xcframework}}"; \
	android_aar="$${ANDROID_AAR:-.build/android/SwiftGodot.aar}"; \
	output_dir="$${OUTPUT_DIR:-.}"; \
	scripts/package-godot-addon "$$tag" "$$xcframework" "$$embed_xcframework" "$$android_aar" "$$output_dir"

check-args:
	@if test x$(VERSION)$(NOTES) = x; then echo You need to provide both VERSION=XX NOTES=FILENAME arguments to this makefile target; exit 1; fi

lint:
	swiftlint lint Sources
