# Third-party notices

These apps are independent clients. The web routing helpers include adaptations from the MIT-licensed magpie GUI.

- [magpie](https://github.com/yetone/magpie) — MIT License, copyright (c) 2026 yetone. Routing helper adaptations are credited below.
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — MIT License. Copyright notices include Miguel de Icaza and other contributors; see `ios/App/Resources/Licenses/LICENSE-SwiftTerm.txt`.
- [Citadel](https://github.com/orlandos-nl/Citadel) — MIT License, copyright (c) 2022 Orlandos; see `ios/App/Resources/Licenses/LICENSE-Citadel.txt`.
- [SwiftNIO](https://github.com/apple/swift-nio), [swift-nio-ssh](https://github.com/Wellz26/swift-nio-ssh), and [swift-crypto](https://github.com/apple/swift-crypto) — transitive dependencies under Apache License 2.0. See each upstream project for current notices and license text.

The bundled license texts under `ios/App/Resources/Licenses/` are presented in the app's Licenses screen.

## Web dashboard

- Preact — MIT License; see `web/node_modules/preact/LICENSE` in an installed dependency tree.
- Vite — MIT License; see `web/node_modules/vite/LICENSE.md` in an installed dependency tree for its license and bundled dependency notices.

The web routing, groups, providers, and quota decoders were written against the JSON contracts in yetone/magpie commit `7660399` (MIT, copyright (c) 2026 yetone), including `internal/gui` and its gateway/provider types. No upstream implementation was copied.

## Routing helpers

`web/src/core/routing-model.ts` and `web/src/core/wire-geometry.ts` adapt semantics, the agent palette, and path construction from yetone/magpie, `internal/gui/assets/plugins/routing/client.js`, commit `7660399`.

MIT License

Copyright (c) 2026 yetone

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
