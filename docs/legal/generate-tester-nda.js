const { Document, Packer, Paragraph, TextRun, Header, Footer, AlignmentType,
        PageNumber, BorderStyle, TabStopType } = require('docx');
const fs = require('fs');
const path = require('path');

const PAGE = {
  size: { width: 12240, height: 15840 },
  margin: { top: 1008, right: 1080, bottom: 1008, left: 1080 },
};
const CONTENT_WIDTH = 12240 - 1080 - 1080;

const FONT = 'Times New Roman';
const SIZE = 22; // 11pt
const SIZE_SM = 18;
const SIZE_TITLE = 28;
const ACCENT = '6B5841';

function t(text, opts = {}) {
  return new TextRun({ text, font: FONT, size: SIZE, ...opts });
}
function bold(text, opts = {}) {
  return t(text, { bold: true, ...opts });
}
function italic(text, opts = {}) {
  return t(text, { italics: true, ...opts });
}

function blank(after = 120) {
  return new Paragraph({ spacing: { after }, children: [] });
}

function p(children, opts = {}) {
  return new Paragraph({
    spacing: { after: 160, line: 276 },
    alignment: AlignmentType.JUSTIFIED,
    ...opts,
    children: Array.isArray(children) ? children : [children],
  });
}

function center(children, opts = {}) {
  return p(children, { alignment: AlignmentType.CENTER, ...opts });
}

function sectionTitle(num, title) {
  return new Paragraph({
    spacing: { before: 280, after: 140, line: 276 },
    children: [bold(`${num}. ${title}`)],
  });
}

function body(text) {
  return p([t(text)]);
}

function bodyRuns(runs) {
  return p(runs);
}

function signatureBlock(partyLabel, partyNameLine) {
  return [
    new Paragraph({
      spacing: { before: 240, after: 80 },
      children: [bold(partyLabel)],
    }),
    new Paragraph({
      spacing: { after: 60 },
      children: [t(partyNameLine)],
    }),
    new Paragraph({
      spacing: { after: 60 },
      children: [t('Name: _______________________________________________')],
    }),
    new Paragraph({
      spacing: { after: 60 },
      children: [t('Title / Role (if any): ________________________________')],
    }),
    new Paragraph({
      spacing: { after: 60 },
      children: [t('Signature: ___________________________________________')],
    }),
    new Paragraph({
      spacing: { after: 60 },
      children: [t('Email: _______________________________________________')],
    }),
    new Paragraph({
      spacing: { after: 200 },
      children: [t('Date: ________________________________________________')],
    }),
  ];
}

const doc = new Document({
  styles: {
    default: {
      document: {
        run: { font: FONT, size: SIZE },
      },
    },
  },
  sections: [
    {
      properties: {
        page: PAGE,
      },
      headers: {
        default: new Header({
          children: [
            new Paragraph({
              alignment: AlignmentType.CENTER,
              border: {
                bottom: { style: BorderStyle.SINGLE, size: 12, color: ACCENT, space: 6 },
              },
              spacing: { after: 100 },
              children: [
                bold('MATTERYA', { size: 20, color: ACCENT }),
                t('  ·  ', { size: SIZE_SM, color: '888888' }),
                t('CONFIDENTIAL — AUTHORIZED TESTERS ONLY', {
                  size: SIZE_SM,
                  bold: true,
                  color: '444444',
                }),
              ],
            }),
          ],
        }),
      },
      footers: {
        default: new Footer({
          children: [
            new Paragraph({
              border: {
                top: { style: BorderStyle.SINGLE, size: 6, color: 'AAAAAA', space: 4 },
              },
              spacing: { before: 80 },
              tabStops: [
                { type: TabStopType.CENTER, position: CONTENT_WIDTH / 2 },
                { type: TabStopType.RIGHT, position: CONTENT_WIDTH },
              ],
              children: [
                t('Matterya Tester NDA', { size: SIZE_SM, color: '555555' }),
                t('\t'),
                t('Page ', { size: SIZE_SM, color: '555555' }),
                new TextRun({ children: [PageNumber.CURRENT], font: FONT, size: SIZE_SM, color: '555555' }),
                t(' of ', { size: SIZE_SM, color: '555555' }),
                new TextRun({ children: [PageNumber.TOTAL_PAGES], font: FONT, size: SIZE_SM, color: '555555' }),
                t('\t'),
                t('legal@matterya.com', { size: SIZE_SM, color: '555555' }),
              ],
            }),
          ],
        }),
      },
      children: [
        center([bold('NON-DISCLOSURE AGREEMENT', { size: SIZE_TITLE })], {
          spacing: { after: 40, line: 276 },
        }),
        center([bold('Beta / Pre-Release Tester', { size: 24 })], {
          spacing: { after: 40, line: 276 },
        }),
        center([t('Matterya', { size: 22, color: ACCENT, bold: true })], {
          spacing: { after: 200, line: 276 },
        }),

        bodyRuns([
          t('This Non-Disclosure Agreement (the “'),
          bold('Agreement'),
          t('”) is entered into as of the date of the last signature below (the “'),
          bold('Effective Date'),
          t('”) by and between:'),
        ]),

        bodyRuns([
          bold('Matterya'),
          t(', the operator of the Matterya social and media application available at '),
          bold('https://matterya.com'),
          t(' (also referred to as “'),
          bold('World App'),
          t('”), with notices to be sent to '),
          bold('legal@matterya.com'),
          t(' (“'),
          bold('Matterya'),
          t(',” “'),
          bold('Company'),
          t(',” “'),
          bold('we'),
          t(',” or “'),
          bold('us'),
          t('”); and'),
        ]),

        bodyRuns([
          t('the individual identified in the signature block below (“'),
          bold('Tester'),
          t(',” “'),
          bold('you'),
          t(',” or “'),
          bold('your'),
          t('”).'),
        ]),

        body('Matterya and Tester may be referred to individually as a “Party” and collectively as the “Parties.”'),

        bodyRuns([
          t('Matterya is developing and operating the Matterya product and related software, services, designs, content systems, APIs, infrastructure, and pre-release materials (collectively, the “'),
          bold('Product'),
          t('”). Matterya wishes to grant Tester limited access to pre-release or limited-release versions of the Product for evaluation and feedback. In connection with that access, Tester may receive confidential information. The Parties agree as follows:'),
        ]),

        // 1
        sectionTitle('1', 'Purpose'),
        body('The purpose of this Agreement is to protect Confidential Information disclosed by Matterya so that Tester may evaluate, use, and provide feedback on the Product in Matterya’s private test program (the “Testing Program”). Tester may use Confidential Information solely for that purpose and for no other purpose.'),

        // 2
        sectionTitle('2', 'Confidential Information'),
        body('“Confidential Information” means all non-public information, materials, and know-how disclosed by or on behalf of Matterya to Tester, whether in written, oral, electronic, visual, or other form, that relates to the Product or Matterya’s business, including without limitation:'),
        body('(a) pre-release builds, TestFlight or other distribution access, invite codes, credentials, APIs, backend endpoints, configuration, feature flags, and unpublished product roadmaps;'),
        body('(b) product designs, user interfaces, user experience flows, prototypes, mockups, wireframes, branding concepts, and unreleased visual assets;'),
        body('(c) source code, object code, architecture, algorithms, data models, performance characteristics, security measures, and technical documentation;'),
        body('(d) business plans, pricing, monetization experiments, partnerships, go-to-market plans, metrics, and internal strategies;'),
        body('(e) non-public content, seed data, demo datasets, moderator tooling, and internal admin or operations workflows;'),
        body('(f) bugs, defects, vulnerabilities, crash logs, and any security findings discovered during testing;'),
        body('(g) the existence of the Testing Program, Tester’s participation, test results, and any feedback, discussions, or communications about unreleased features; and'),
        body('(h) any other information that a reasonable person would understand to be confidential given its nature or the circumstances of disclosure, whether or not marked “confidential.”'),
        body('Confidential Information also includes notes, summaries, screenshots, recordings, analyses, and other materials prepared by Tester that contain or reflect any of the foregoing. Confidential Information includes trade secrets within the meaning of applicable German law (including the German Trade Secrets Act (Geschäftsgeheimnisgesetz – GeschGehG)).'),

        // 3
        sectionTitle('3', 'Exclusions'),
        body('Confidential Information does not include information that Tester can demonstrate:'),
        body('(a) is or becomes publicly available through no fault or breach by Tester;'),
        body('(b) was rightfully in Tester’s possession without confidentiality obligations before disclosure by Matterya;'),
        body('(c) is independently developed by Tester without use of or reference to Confidential Information; or'),
        body('(d) is rightfully received from a third party without breach of any confidentiality obligation.'),
        body('If Tester is required by law, regulation, or court order to disclose Confidential Information, Tester will (to the extent legally permitted) give Matterya prompt written notice so Matterya may seek a protective order or other remedy, and will disclose only the minimum information legally required.'),

        // 4
        sectionTitle('4', 'Tester Obligations'),
        body('Tester agrees to:'),
        body('(a) hold all Confidential Information in strict confidence and not disclose it to any third party without Matterya’s prior written consent;'),
        body('(b) use Confidential Information solely to participate in the Testing Program and provide feedback to Matterya;'),
        body('(c) not reverse engineer, decompile, disassemble, or otherwise attempt to derive source code or underlying ideas from the Product, except to the limited extent that applicable law (including mandatory provisions of German or EU law) expressly prohibits this restriction;'),
        body('(d) not copy, photograph, screen-record, stream, publish, post, blog, or otherwise share Confidential Information, Product screenshots, videos, or descriptions of unreleased features on any public or semi-public channel (including social media, forums, community chats, app store reviews, press, or private groups with non-testers), unless Matterya has given prior written approval for a specific disclosure;'),
        body('(e) not grant access to the Product, invite codes, builds, or accounts to any other person; Tester will keep login credentials secure and will not share devices or accounts used for testing with non-authorized persons;'),
        body('(f) promptly notify Matterya at legal@matterya.com if Tester becomes aware of any unauthorized use or disclosure of Confidential Information or any security vulnerability;'),
        body('(g) follow any additional written testing guidelines Matterya provides (for example, bug-report channels, severity labels, or no-public-discussion rules); and'),
        body('(h) upon Matterya’s request, or upon termination of Tester’s participation, promptly cease use of the Product, delete or destroy Confidential Information in Tester’s possession or control (including local builds, screenshots, and notes), and confirm such deletion in writing if requested, except for copies retained solely as required by law or ordinary automated backup systems that are not readily accessible, which remain subject to this Agreement.'),

        // 5
        sectionTitle('5', 'Feedback'),
        body('Tester may provide ideas, suggestions, bug reports, usability comments, ratings, and other feedback regarding the Product (“Feedback”). To the fullest extent permitted by law, Tester grants Matterya a perpetual, irrevocable, worldwide, exclusive, royalty-free, fully paid, transferable, and sublicensable right and license to use, reproduce, modify, adapt, publish, distribute, commercialize, and otherwise exploit Feedback for any purpose, without restriction, obligation, or compensation to Tester. Where German copyright law applies, Tester additionally waives, to the extent legally permitted, any claims to remuneration and agrees not to assert moral rights against Matterya’s permitted use of Feedback. Feedback is not Confidential Information of Tester.'),

        // 6
        sectionTitle('6', 'No License; Ownership'),
        body('All Confidential Information and the Product remain the exclusive property of Matterya and its licensors. Nothing in this Agreement grants Tester any license, ownership interest, or other rights in the Product, Confidential Information, trademarks, or intellectual property, except the limited, revocable, non-transferable, non-exclusive right to access and use the Product solely for the Testing Program under Matterya’s then-current testing terms. Tester will not remove or alter proprietary notices.'),

        // 7
        sectionTitle('7', 'No Publicity'),
        body('Except as required by law, Tester will not issue press releases, public statements, or marketing materials referring to Matterya, the Product, or the Testing Program, or implying endorsement, partnership, or employment, without Matterya’s prior written consent.'),

        // 8
        sectionTitle('8', 'No Warranty; Testing Nature'),
        body('The Product and all Confidential Information are provided “as is” and “as available.” Pre-release software may be incomplete, unstable, inaccurate, or insecure, and may change or be withdrawn at any time. Tester participates voluntarily and at Tester’s own risk. Matterya has no obligation to release any feature, continue the Testing Program, or provide support. Statutory warranty rights, if any, that cannot be excluded under mandatory German law remain unaffected to the extent applicable.'),

        // 9
        sectionTitle('9', 'Liability'),
        body('Matterya’s liability is limited as follows, subject always to mandatory German law:'),
        body('(a) Matterya is liable without limitation for intent (Vorsatz) and gross negligence (grobe Fahrlässigkeit); for injury to life, body, or health; and under the German Product Liability Act (Produkthaftungsgesetz) or other mandatory liability regimes that cannot be limited.'),
        body('(b) In cases of simple negligence (einfache Fahrlässigkeit), Matterya is liable only for breach of essential contractual obligations (Kardinalpflichten) — obligations whose fulfillment is a prerequisite for proper performance of this Agreement and on which Tester may regularly rely — and only for the foreseeable damage typical for this type of agreement.'),
        body('(c) Subject to subsections (a) and (b), Matterya’s aggregate liability arising out of or related to this Agreement or the Testing Program is limited to one hundred euro (EUR 100).'),
        body('(d) The limitations in this Section apply to Matterya’s legal representatives, employees, and agents to the same extent.'),

        // 10
        sectionTitle('10', 'Term and Survival'),
        body('This Agreement begins on the Effective Date and continues until terminated by either Party upon written notice (including email to legal@matterya.com for notices to Matterya). Matterya may suspend or end Tester’s access to the Product at any time. Sections 2–7, 9–15, and any other provisions that by their nature should survive, will survive termination. Tester’s confidentiality obligations continue for five (5) years after termination; provided that trade secrets remain protected for so long as they qualify as trade secrets under applicable law.'),

        // 11
        sectionTitle('11', 'Remedies'),
        body('Tester acknowledges that unauthorized use or disclosure of Confidential Information may cause irreparable harm for which monetary damages may be inadequate. Matterya is entitled to seek injunctive relief (including interim measures such as a temporary injunction / einstweilige Verfügung) and any other remedies available under German law, in addition to claims for damages.'),

        // 12
        sectionTitle('12', 'No Employment or Compensation'),
        body('Nothing in this Agreement creates an employment, agency, partnership, or joint venture relationship. Unless Matterya and Tester enter into a separate written agreement, Tester is not entitled to compensation, equity, benefits, or reimbursement for participation in the Testing Program. Tester is responsible for any taxes arising from any optional incentives Matterya may separately offer.'),

        // 13
        sectionTitle('13', 'Export and Legal Compliance'),
        body('Tester will comply with all applicable laws in connection with the Testing Program, including export control and sanctions laws of Germany, the European Union, and other applicable jurisdictions. Tester represents that Tester is not prohibited by law from receiving the Product or Confidential Information.'),

        // 14
        sectionTitle('14', 'Governing Law and Jurisdiction'),
        body('This Agreement is governed by the laws of the Federal Republic of Germany, excluding its conflict-of-laws rules and excluding the United Nations Convention on Contracts for the International Sale of Goods (CISG).'),
        body('If Tester is a merchant (Kaufmann), a legal entity under public law, or a special fund under public law, or if Tester has no general place of jurisdiction in Germany, the exclusive place of jurisdiction for all disputes arising out of or in connection with this Agreement is the competent courts in the State of North Rhine-Westphalia (Nordrhein-Westfalen), Germany, at Matterya’s principal place of business. Matterya may also bring proceedings at Tester’s general place of jurisdiction. Mandatory consumer venue rules remain unaffected where Tester is a consumer (Verbraucher) within the meaning of Section 13 of the German Civil Code (BGB).'),

        // 15
        sectionTitle('15', 'General'),
        body('(a) Entire Agreement. This Agreement constitutes the entire agreement between the Parties regarding its subject matter and supersedes prior or contemporaneous agreements on that subject. If Matterya also presents in-app or program-specific terms of use for testers, those terms apply in addition to this Agreement; if there is a direct conflict on confidentiality, this Agreement controls.'),
        body('(b) Amendments. Amendments must be in text form (Textform) within the meaning of Section 126b BGB (for example, email or electronic acceptance), or in writing if mandatory law requires a stricter form.'),
        body('(c) Assignment. Tester may not assign or transfer this Agreement without Matterya’s prior written consent. Matterya may assign this Agreement to an affiliate or successor in connection with a merger, acquisition, corporate reorganization, or sale of assets.'),
        body('(d) Severability. If any provision is held invalid or unenforceable, the remaining provisions remain in full force. The invalid provision will be replaced by a valid provision that most closely reflects the economic purpose of the invalid provision.'),
        body('(e) Waiver. Failure to enforce any provision is not a waiver of future enforcement of that or any other provision.'),
        body('(f) Notices. Notices under this Agreement may be sent by email. Notices to Matterya must be sent to legal@matterya.com. Notices to Tester may be sent to the email address Tester provides. Notices are deemed received when sent if no delivery-failure notice is received.'),
        body('(g) Counterparts / Electronic Signatures. This Agreement may be executed in counterparts (including PDF or electronic signature platforms), each of which is deemed an original, and all of which together constitute one instrument. Electronic signatures and acceptance are effective to the extent permitted by applicable law.'),
        body('(h) Language. This Agreement is executed in English. The English version controls.'),
        body('(i) Interpretation. Headings are for convenience only. “Including” means “including without limitation.”'),

        blank(200),
        body('IN WITNESS WHEREOF, the Parties have executed this Agreement as of the Effective Date.'),

        blank(80),
        ...signatureBlock('MATTERYA', 'Matterya  ·  legal@matterya.com  ·  matterya.com'),
        blank(40),
        ...signatureBlock('TESTER', 'Individual tester participant'),

        blank(160),
        center([italic('— End of Agreement —', { size: SIZE_SM, color: '555555' })], {
          spacing: { after: 80 },
        }),
      ],
    },
  ],
});

const outPath = path.join(__dirname, 'Matterya-Tester-NDA.docx');
Packer.toBuffer(doc).then((buffer) => {
  fs.writeFileSync(outPath, buffer);
  console.log('Wrote', outPath);
}).catch((err) => {
  console.error(err);
  process.exit(1);
});
