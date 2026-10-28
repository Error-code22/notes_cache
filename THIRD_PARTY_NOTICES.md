# Third-party notices

Foluma bundles open-source software. This file lists the components that are
most important to the offline document readers. Full licence texts are included
with the corresponding packages and, where applicable, under
`assets/readers/`.

## Document renderers

### docx-preview
- Project: https://github.com/VolodymyrBaydalka/docxjs
- Licence: Apache-2.0
- Location: `assets/readers/docx-preview.min.js`
- Licence text: `assets/readers/LICENSE-docx-preview.txt`

### JSZip
- Project: https://github.com/Stuk/jszip
- Licence: MIT or GPL-3.0; Foluma uses the MIT option.
- Location: `assets/readers/jszip3.min.js`
- Licence text: `assets/readers/LICENSE-jszip.txt`

### SheetJS Community Edition
- Project: https://github.com/SheetJS/sheetjs
- Licence: Apache-2.0
- Location: `assets/readers/xlsx.full.min.js`
- Licence text: `assets/readers/LICENSE-sheetjs.txt`

### PPTX
- Foluma reads `.pptx` files with its own zip/XML text extractor
  (`lib/editors/office_pptx.dart`). No third-party PPTX renderer is bundled.

### archive and xml (Dart)
- `archive`: https://pub.dev/packages/archive (MIT)
- `xml`: https://pub.dev/packages/xml (MIT)
- Used for the offline EPUB parser.

## Flutter and native components

### webview_flutter
- Project: https://pub.dev/packages/webview_flutter
- Licence: BSD-3-Clause
- Used to host the local, offline Office and EPUB viewers.

### pdfrx
- Project: https://pub.dev/packages/pdfrx
- Licence: MIT
- Used for PDF rendering, search and page rendering for OCR.

### flutter_pdf_annotations
- Project: https://pub.dev/packages/flutter_pdf_annotations
- Licence: MIT
- Used for the native PDF annotation and signature-stamp editor.

### google_mlkit_text_recognition
- Project: https://pub.dev/packages/google_mlkit_text_recognition
- Licence: MIT
- Used for on-device OCR. Recognition runs locally through ML Kit; Foluma does
  not upload the rendered page.

### pdf_manipulator
- Project: https://pub.dev/packages/pdf_manipulator
- Licence: MIT
- Used for local PDF page rotation, deletion and reordering. The dependency is
  configured with an empty `keep` set, so only its always-included core engine
  is packaged (no render/office/extract modules).

## Notes

- The Office and EPUB viewers make no document-conversion request to a server.
- The viewer pages include a Content-Security-Policy that blocks network
  connections from document content.
- This list is not a complete dependency inventory. The in-app
  **Settings → Open source licences** page includes the full licence texts
  registered by Flutter and every bundled package.
- Flutter packages also retain their own licence files in the pub cache; review
  the final inventory before publishing a store release.
