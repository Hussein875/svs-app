/**
 * Normalized PDF placements (0…1, UIKit-style: origin top-left).
 * Must stay in sync with CompanyDocument.swift for each documentId.
 */

export type NormalizedPlacement = {
  pageIndex: number;
  x: number;
  y: number;
  width: number;
  height: number;
};

export type DocumentSigningTemplate = {
  id: string;
  title: string;
  accidentDatePrefix: string;
  signature: NormalizedPlacement;
  signingDate: NormalizedPlacement;
  accidentDate: NormalizedPlacement;
};

export const DOCUMENT_SIGNING_TEMPLATES:
Record<string, DocumentSigningTemplate> = {
  "av-wessels": {
    id: "av-wessels",
    title: "Wessels – Anwaltsvollmacht",
    accidentDatePrefix: "Verkehrsunfall vom ",
    // Kalibriert auf A4 (595×842 pt).
    signature: {
      pageIndex: 0, x: 0.077, y: 0.762, width: 0.36, height: 0.085,
    },
    signingDate: {
      pageIndex: 0, x: 0.588, y: 0.788, width: 0.28, height: 0.045,
    },
    accidentDate: {
      pageIndex: 0, x: 0.232, y: 0.153, width: 0.55, height: 0.045,
    },
  },
};

/**
 * Returns a supported template or null.
 *
 * @param {string} documentId Document identifier.
 * @return {DocumentSigningTemplate | null} Template metadata.
 */
export function getDocumentSigningTemplate(
  documentId: string
): DocumentSigningTemplate | null {
  return DOCUMENT_SIGNING_TEMPLATES[String(documentId ?? "").trim()] ?? null;
}
