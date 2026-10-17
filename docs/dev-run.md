# Local development / 本機開發

## Web mock / 網頁模擬資料

```sh
cd web
npm ci
npm run dev
```

Open the Vite URL printed in the terminal with `/?mock=1`. Mock mode uses sanitized fixtures and needs no real upstream. 模擬模式不需要連接真實主機。

```sh
cd web
npm test
npm run build
npx playwright install chromium
npm run screenshots
```

Screenshots land in `web/docs/screenshots`; CI's `web-screenshots` job uploads `web-mock-screenshots`. Tests can also be run with `npx playwright test` after browser installation.

## Collector / 採集器

```sh
cd collector
go build -o magpie-collector ./cmd/magpie-collector
./magpie-collector
# In another terminal, with the configured read header if applicable:
curl http://127.0.0.1:8787/v1/collector/hello
GOCACHE=/tmp/gocache GOPATH=/tmp/gopath go vet ./...
GOCACHE=/tmp/gocache GOPATH=/tmp/gopath go test ./...
```

See [collector README](../collector/README.md) for env/config and write guards. 預設只監聽本機，動作關閉。

## Swift packages / Swift 套件

```sh
swift test --package-path ios/Packages/MagpieKit
swift test --package-path ios/Packages/SSHKit
```

In restricted environments where SwiftPM stalls, MagpieKit can be typechecked (this does not run tests):

```sh
. ~/.local/share/swiftly/env.sh
swiftc -typecheck -module-name MagpieKit -module-cache-path /tmp/mc $(find ios/Packages/MagpieKit/Sources -name '*.swift')
```

## iOS simulator screenshots / 模擬器截圖

In GitHub Actions, open **CI → Run workflow** (`workflow_dispatch`) on the desired branch. This runs existing package/build jobs plus the collector checks, web checks, and both screenshot jobs. The `screenshots` job builds with XcodeGen on macOS, launches the simulator with `-isMockMode YES -initialTab N`, and captures overview/activity/tmux/agent/services plus dark overview and Agent routing/usage/providers captures. Download artifact **`mock-screenshots`**. The unsigned device build is **`magpie-ios-ipa`**; web captures are **`web-mock-screenshots`**. No deployment occurs.

在 Actions 手動執行 CI，完成後於該次執行的 Artifacts 下載；不需真實服務連線。詳見 [workflow](../.github/workflows/ci.yml)。
