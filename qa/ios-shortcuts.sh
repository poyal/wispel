#!/bin/bash
# Run from the dedicated Mac QA directory containing ios-phone/ and Derived/.
set -eu
sim=${1:?Pass the booted test simulator UDID}
stage=${2:?Pass the simulator Files staging directory}
[[ -d "$stage" && -d ios-phone/Shortcuts && -d Derived ]]
qa_dir="$PWD"
logs="$qa_dir/shortcut-results"
mkdir -p "$logs"
cd ios-phone
args=(-scheme Wispel -destination "id=$sim" -derivedDataPath "$qa_dir/Derived" -parallel-testing-enabled NO)
xcodebuild "${args[@]}" build-for-testing >"$logs/build.log" 2>&1
run_ui() {
    xcodebuild "${args[@]}" "-only-testing:WispelUITests/WispelUITests/$1" test-without-building >"$logs/$2.log" 2>&1
}
run_shortcut() {
    xcrun simctl openurl "$sim" "shortcuts://run-shortcut?name=Wispel-$1${2:-}"
}
for name in ${WISPEL_QA_KINDS:-Sms Slack Mail Call}; do
    kind=$(printf %s "$name" | tr '[:upper:]' '[:lower:]')
    title="$name${WISPEL_QA_NAME_SUFFIX:-}"
    cp "Shortcuts/$kind.shortcut" "$stage/Wispel-$title.shortcut"
    export TEST_RUNNER_WISPEL_QA_SHORTCUT_FILE=1 TEST_RUNNER_WISPEL_QA_SHORTCUT_NAME="Wispel-$title"
    if ! run_ui testImportSignedShortcut "$kind-import"; then echo "FAIL import $kind"; continue; fi
    if [[ "$name" == Call ]]; then
        run_shortcut "$title" '&input=text&text=QA%20incoming'
    else
        run_shortcut "$title"
    fi
    sleep 3
    export TEST_RUNNER_WISPEL_QA_RUN_SHORTCUT=1
    if ! run_ui testRunImportedShortcut "$kind-permission"; then echo "CHECK permission $kind"; fi
    sleep 2
    if [[ "$name" == Call ]]; then
        run_shortcut "$title" '&input=text&text=QA%0A%EB%B6%80%EC%9E%AC%EC%A4%91%20%EC%A0%84%ED%99%94'
        sleep 4
    fi
    echo "Executed $kind. Compare each resulting event and Android acknowledgement on the relay."
done
