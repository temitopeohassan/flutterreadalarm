import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// A small EPUB 3 with a nav document, two chapters and a cover page that
/// has no text.
Uint8List buildEpub({bool drm = false}) {
  final archive = Archive();
  void add(String name, String text) {
    final data = utf8.encode(text);
    archive.addFile(ArchiveFile(name, data.length, data));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');
  if (drm) {
    add('META-INF/encryption.xml', '''<?xml version="1.0"?>
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"
    xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
  <enc:EncryptedData>
    <enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/>
  </enc:EncryptedData>
</encryption>''');
  }
  add('OEBPS/content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>The Quiet Morning</dc:title>
    <dc:creator>Ada Writer</dc:creator>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="cover" href="text/cover.xhtml" media-type="application/xhtml+xml"/>
    <item id="c1" href="text/chapter%201.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/chapter2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="cover"/>
    <itemref idref="c1"/>
    <itemref idref="c2"/>
  </spine>
</package>''');
  add('OEBPS/nav.xhtml',
      '''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<body><nav epub:type="toc"><ol>
  <li><a href="text/chapter%201.xhtml">One: The Kettle</a></li>
  <li><a href="text/chapter2.xhtml#start">Two: The Bus</a></li>
</ol></nav></body></html>''');
  add('OEBPS/text/cover.xhtml',
      '<html><body><img src="cover.jpg"/></body></html>');
  add('OEBPS/text/chapter 1.xhtml', '''<html><head><title>ignored</title>
<style>p { color: red; }</style></head><body>
<h1>Chapter One</h1>
<p>The morning light came in low. She had promised herself one chapter!</p>
<p>The kettle clicked off<script>alert(1)</script>, and the house went quiet.</p>
</body></html>''');
  add('OEBPS/text/chapter2.xhtml', '''<html><body>
<h2 id="start">Chapter Two</h2>
<p>Somewhere outside, a bus pulled away. She turned the page?</p>
</body></html>''');
  return ZipEncoder().encodeBytes(archive);
}

/// A two-page PDF with document info, one line of text per page.
Uint8List buildPdf({List<String>? pages, String title = 'Pocket Guide'}) {
  final doc = PdfDocument();
  doc.documentInformation.title = title;
  doc.documentInformation.author = 'Sam Author';
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
  for (final text in pages ??
      const [
        'First page opens here. It has two sentences.',
        'Second page follows. The end is near.',
      ]) {
    doc.pages
        .add()
        .graphics
        .drawString(text, font, bounds: const Rect.fromLTWH(20, 20, 500, 40));
  }
  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return bytes;
}
