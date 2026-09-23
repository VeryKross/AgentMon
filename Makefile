.PHONY: build test test-relay app dmg run demo clean

build:
	swift build

test:
	swift test

test-relay:
	sh scripts/test-relay.sh

app:
	sh scripts/package-app.sh

dmg:
	sh scripts/create-dmg.sh

run:
	swift run AgentMon

demo:
	swift run AgentMon --demo

clean:
	swift package clean
