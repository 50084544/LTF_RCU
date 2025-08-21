import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

void main() {
  // Example Base64-encoded SAMLResponse (replace with your actual data)
  const base64Response = 'eJzLKCkpKLbS1y8qTi3W0y8qSs7ILypRslIqzy/KSVEEABxVB44=';

  // Step 1: Decode base64
  final compressedData = base64.decode(base64Response);

  // Step 2: Decompress using raw DEFLATE
  final decompressedBytes = ZLibDecoder().decodeBytes(compressedData);

  // Step 3: Convert to string
  final xmlString = utf8.decode(decompressedBytes);

  // Step 4: Parse XML
  final document = XmlDocument.parse(xmlString);

  // Step 5: Extract the email attribute safely (Option A)
  XmlElement? emailAttr;
  try {
    emailAttr = document.findAllElements('Attribute').firstWhere(
          (attr) =>
              attr.getAttribute('Name') ==
              'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress',
        );
  } catch (e) {
    emailAttr = null;
  }

  if (emailAttr != null) {
    final emailValue = emailAttr.findElements('AttributeValue').first.text;
  } else {}
}
