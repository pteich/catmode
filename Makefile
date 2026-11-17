.PHONY: app run test install clean icon zip

APP  := build/CatMode.app
# ad-hoc; set to a real identity so the Accessibility grant survives rebuilds
SIGN ?= -

app:
	mkdir -p $(APP)/Contents/MacOS
	mkdir -p $(APP)/Contents/Resources
	cp Info.plist $(APP)/Contents/
	cp AppIcon.icns $(APP)/Contents/Resources/
	# universal binary: Apple Silicon + Intel
	swiftc -O -swift-version 5 -target arm64-apple-macos13 main.swift -o build/CatMode-arm64
	swiftc -O -swift-version 5 -target x86_64-apple-macos13 main.swift -o build/CatMode-x86_64
	lipo -create -output $(APP)/Contents/MacOS/CatMode build/CatMode-arm64 build/CatMode-x86_64
	codesign --force -s "$(SIGN)" $(APP)

# Always launch via open, so Accessibility is granted to CatMode and not your terminal
run: app
	open $(APP)

test:
	mkdir -p build
	swiftc -swift-version 5 main.swift -o build/catmode-test && build/catmode-test --selftest

install: app
	rm -rf /Applications/CatMode.app
	cp -R $(APP) /Applications/CatMode.app

# Regenerate AppIcon.icns from icon.swift (the .icns is kept in the repo)
icon:
	rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
	swift icon.swift build/icon.png
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s build/icon.png --out build/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
		sips -z $$((s*2)) $$((s*2)) build/icon.png --out build/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns build/AppIcon.iconset -o AppIcon.icns

# Release archive (ditto keeps the bundle's signature and attributes intact)
zip: app
	ditto -c -k --keepParent $(APP) build/CatMode.zip

clean:
	rm -rf build
