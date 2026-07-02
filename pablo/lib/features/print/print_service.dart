// print_service.dart — build a print PDF from rendered images and hand it to
// the OS print dialog (Picasa parity §10 Print / contact sheet).
//
// buildPrintDocument is pure (pdf is pure Dart): it lays the images into pages
// per print_layouts and is unit-testable in the VM with no AppKit. runPrint
// wires it to the app — resolve photos, pick a layout, render temp copies via
// render_service, build the doc, and call Printing.layoutPdf (the native
// NSPrintOperation dialog on macOS).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../backend/native_backend.dart';
import '../../data/models.dart';
import '../export/render_service.dart';
import 'print_dialog.dart';
import 'print_layouts.dart';

/// One printable item: an image file plus the caption to show under it (contact
/// sheet only).
class PrintItem {
  const PrintItem({required this.path, required this.caption});
  final String path;
  final String caption;
}

/// Build a print-ready [pw.Document] laying [items] out per [layout] on
/// [format] pages. Missing/unreadable image files are skipped. Pure — no
/// platform channels — so it runs in a plain VM test.
pw.Document buildPrintDocument(
  List<PrintItem> items,
  PrintLayout layout, {
  PdfPageFormat format = PdfPageFormat.letter,
}) {
  final doc = pw.Document();
  // Decode each image once (indexed to match layoutPages' indices).
  final images = <int, pw.MemoryImage>{};
  for (var i = 0; i < items.length; i++) {
    try {
      final bytes = File(items[i].path).readAsBytesSync();
      images[i] = pw.MemoryImage(Uint8List.fromList(bytes));
    } catch (_) {
      // Unreadable → leave a blank cell rather than aborting the whole job.
    }
  }

  final pages = layoutPages(items.length, layout);
  for (final cells in pages) {
    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) {
          final w = format.availableWidth;
          final h = format.availableHeight;
          return pw.Stack(
            children: [
              for (final cell in cells)
                pw.Positioned(
                  left: cell.left * w,
                  top: cell.top * h,
                  child: pw.SizedBox(
                    width: cell.width * w,
                    height: cell.height * h,
                    child: pw.Column(
                      mainAxisSize: pw.MainAxisSize.max,
                      children: [
                        pw.Expanded(
                          child: images[cell.index] == null
                              ? pw.SizedBox()
                              : pw.Image(images[cell.index]!,
                                  fit: pw.BoxFit.contain),
                        ),
                        if (cell.caption)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 2),
                            child: pw.Text(
                              items[cell.index].caption,
                              style: const pw.TextStyle(fontSize: 6),
                              maxLines: 1,
                              overflow: pw.TextOverflow.clip,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
  return doc;
}

/// Print [photos] (defaults to a resolver at the call site). Shows the layout
/// picker, renders each photo to a temp copy, builds the PDF, and opens the OS
/// print dialog.
Future<void> runPrint(
  BuildContext context, {
  required List<Photo> photos,
}) async {
  final backend = NativeBackendScope.maybeOf(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (photos.isEmpty) {
    messenger?.showSnackBar(
        const SnackBar(content: Text('Nothing selected to print.')));
    return;
  }
  if (backend == null) {
    messenger?.showSnackBar(
        const SnackBar(content: Text('Printing needs the native backend.')));
    return;
  }

  final layout = await showPrintDialog(context, count: photos.length);
  if (layout == null) return;

  final dim = renderDimFor(layout);
  final items = <PrintItem>[];
  for (final p in photos) {
    final path = await renderTempCopy(
      engine: backend.engine,
      events: backend.events,
      photo: p,
      maxDim: dim,
    );
    if (path != null) items.add(PrintItem(path: path, caption: p.label));
  }
  if (items.isEmpty) {
    messenger?.showSnackBar(
        const SnackBar(content: Text('Could not prepare pages to print.')));
    return;
  }

  final doc = buildPrintDocument(items, layout);
  await Printing.layoutPdf(onLayout: (format) async => doc.save());
}
