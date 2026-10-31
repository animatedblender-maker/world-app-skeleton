/**
 * Matterya moderation policy decision tree.
 *
 * Moderators only answer questions (keyboard shortcuts). They never choose
 * Remove vs Mark — each leaf has a policy outcome we can tune together later.
 *
 * outcome:
 *   remove  — take content down / archive
 *   mark    — keep live, tagged for mature/sensitive surfaces
 *   dismiss — false positive / allowed; clear flags
 */
import type { ModerationCategorySlug } from './categories.js';

export type PolicyOutcome = 'remove' | 'mark' | 'dismiss';

export type PolicyLeaf = {
  kind: 'leaf';
  id: string;
  label: string;
  /** Root archive/category bucket */
  root: ModerationCategorySlug;
  outcome: PolicyOutcome;
  /** Short policy rationale (ops only; not shown as Remove/Mark). */
  rationale?: string;
  /** Escalation weight for account strikes. Only relevant when outcome is remove. */
  severity?: 'mild' | 'severe';
};

export type PolicyBranch = {
  kind: 'branch';
  id: string;
  /** Question shown at this step */
  question: string;
  options: PolicyOption[];
};

export type PolicyOption = {
  /** Key shown to mods: 1-9, 0, A-Z */
  key: string;
  label: string;
  node: PolicyNode;
};

export type PolicyNode = PolicyBranch | PolicyLeaf;

/**
 * Escalation leaves — only for platform-style special cases
 * (child safety, imminent violence, suicide crisis, specialist second look).
 * Not offered as a general “I’m unsure of the category” shortcut everywhere.
 */
function escalationChildSafety(root: ModerationCategorySlug = 'mature'): PolicyLeaf {
  return leaf(
    'escalation.child_safety',
    'Escalate — child sexual exploitation / grooming',
    root,
    'remove',
    {
      severity: 'severe',
      rationale:
        'Zero-tolerance child safety (Meta CSEAN / Discord / Snap / X). Remove + account queue; preserve archive for reporting.',
    }
  );
}

function escalationImminentViolence(
  root: ModerationCategorySlug = 'harassment'
): PolicyLeaf {
  return leaf(
    'escalation.imminent_violence',
    'Escalate — imminent real-world violence',
    root,
    'remove',
    {
      severity: 'severe',
      rationale:
        'Credible + imminent threat (Meta / TikTok / Discord). Remove + instant account review.',
    }
  );
}

function escalationSuicideCrisis(): PolicyLeaf {
  return leaf(
    'escalation.suicide_crisis',
    'Escalate — active suicide crisis with plan',
    'self_harm',
    'remove',
    {
      severity: 'severe',
      rationale:
        'Imminent self-harm plan (X / Meta / TikTok). Remove instructional/crisis-plan content + account review; ideation seeking help stays on the normal path.',
    }
  );
}

function escalationSecondLook(): PolicyLeaf {
  return leaf(
    'escalation.second_look',
    'Escalate — needs specialist second look',
    'other',
    'mark',
    {
      rationale:
        'High-stakes but outcome unclear. Keep tagged for senior review — do not use for ordinary uncertainty.',
    }
  );
}

function escalationRootTree(): PolicyNode {
  return branch('escalation', 'What special case needs escalation?', [
    {
      key: '1',
      label: 'Child sexual exploitation / grooming (minor involved)',
      node: escalationChildSafety('mature'),
    },
    {
      key: '2',
      label: 'Imminent real-world violence / swatting',
      node: escalationImminentViolence('violence'),
    },
    {
      key: '3',
      label: 'Active suicide crisis with a concrete plan',
      node: escalationSuicideCrisis(),
    },
    {
      key: '4',
      label: 'Specialist second look (high-stakes, outcome unclear)',
      node: escalationSecondLook(),
    },
  ]);
}

/** Root of the live decision tree. */
export const POLICY_TREE: PolicyBranch = {
  kind: 'branch',
  id: 'root',
  question: 'Is there a policy violation?',
  options: [
    {
      key: '1',
      label: 'Yes — there is a violation',
      node: {
        kind: 'branch',
        id: 'violation_kind',
        question: 'What kind of violation?',
        // Ordered by harm priority (highest first). Mature is mid/low — child-safety
        // still escalates via its own gate; unlabeled adult content is not top priority.
        options: [
          { key: '1', label: 'Self-harm / suicide', node: selfHarmTree() },
          { key: '2', label: 'Terrorism', node: terrorismTree() },
          { key: '3', label: 'Violence / graphic harm', node: violenceTree() },
          { key: '4', label: 'Harassment / bullying', node: harassmentTree() },
          { key: '5', label: 'Hate speech', node: hateTree() },
          { key: '6', label: 'Doxxing / privacy', node: doxxingTree() },
          { key: '7', label: 'Scam / fraud', node: scamTree() },
          { key: '8', label: 'Misinformation', node: misinfoTree() },
          { key: '9', label: 'Mature / sexual content', node: matureTree() },
          { key: 'S', label: 'Spam', node: spamTree() },
          {
            key: '0',
            label: 'Other / not listed',
            node: leaf('other.unlisted', 'Other unlisted violation', 'other', 'mark', {
              rationale: 'Catch-all until policy refined',
            }),
          },
        ],
      },
    },
    {
      key: '2',
      label: 'No — allow / false positive',
      node: leaf(
        'allowed.false_positive',
        'No violation / false positive',
        'other',
        'dismiss',
        { rationale: 'Clears auto flags; content stays' }
      ),
    },
    {
      key: '3',
      label: 'Escalate — special safety case',
      node: escalationRootTree(),
    },
  ],
};

function leaf(
  id: string,
  label: string,
  root: ModerationCategorySlug,
  outcome: PolicyOutcome,
  opts?: { rationale?: string; severity?: 'mild' | 'severe' }
): PolicyLeaf {
  return {
    kind: 'leaf',
    id,
    label,
    root,
    outcome,
    rationale: opts?.rationale,
    severity: opts?.severity ?? (outcome === 'remove' ? 'mild' : undefined),
  };
}

function branch(id: string, question: string, options: PolicyOption[]): PolicyBranch {
  return { kind: 'branch', id, question, options };
}

function spamTree(): PolicyNode {
  return branch('spam', 'What kind of spam?', [
    {
      key: '1',
      label: 'Commercial / unsolicited promo',
      node: leaf('spam.commercial', 'Commercial spam', 'spam', 'remove'),
    },
    {
      key: '2',
      label: 'Repetitive flooding',
      node: leaf('spam.flooding', 'Flooding / repetitive posts', 'spam', 'remove'),
    },
    {
      key: '3',
      label: 'Engagement bait / clickfarm',
      node: leaf('spam.engagement_bait', 'Engagement bait', 'spam', 'remove'),
    },
    {
      key: '4',
      label: 'Malware / phishing link',
      node: leaf('spam.malware', 'Malware or phishing', 'spam', 'remove', {
        severity: 'severe',
        rationale: 'Credential theft / device compromise — escalate account',
      }),
    },
    {
      key: '5',
      label: 'Borderline promo (context OK)',
      node: leaf('spam.borderline_promo', 'Borderline promo', 'spam', 'mark'),
    },
  ]);
}

function harassmentTree(): PolicyNode {
  return branch('harassment', 'What kind of harassment?', [
    {
      key: '1',
      label: 'Bullying',
      node: branch('harassment.bullying', 'What kind of bullying?', [
        {
          key: '1',
          label: 'Targeted cursing / insults',
          node: leaf(
            'harassment.bullying.targeted_cursing',
            'Targeted cursing',
            'harassment',
            'remove'
          ),
        },
        {
          key: '2',
          label: 'Use of slurs (non-hate-group context)',
          node: leaf('harassment.bullying.slurs', 'Slurs in bullying', 'harassment', 'remove'),
        },
        {
          key: '3',
          label: 'Humiliation / mockery of a person',
          node: leaf(
            'harassment.bullying.humiliation',
            'Humiliation / mockery',
            'harassment',
            'remove'
          ),
        },
        {
          key: '4',
          label: 'Encouraging others to pile on',
          node: leaf(
            'harassment.bullying.pile_on',
            'Encouraging pile-on',
            'harassment',
            'remove'
          ),
        },
        {
          key: '5',
          label: 'Mild rude disagreement (not targeted)',
          node: leaf(
            'harassment.bullying.mild_rude',
            'Mild rude disagreement',
            'harassment',
            'dismiss'
          ),
        },
      ]),
    },
    {
      key: '2',
      label: 'Threats of violence',
      node: branch('harassment.threats', 'How credible / severe?', [
        {
          key: '1',
          label: 'Credible / specific threat',
          node: branch(
            'harassment.threats.credible_gate',
            'Is the harm imminent or ongoing (time, place, or swatting)?',
            [
              {
                key: '1',
                label: 'Yes — imminent / ongoing → escalate',
                node: escalationImminentViolence('violence'),
              },
              {
                key: '2',
                label: 'Credible but not imminent',
                node: leaf(
                  'harassment.threats.credible',
                  'Credible threat of violence',
                  'harassment',
                  'remove',
                  { severity: 'severe' }
                ),
              },
            ]
          ),
        },
        {
          key: '2',
          label: 'Hyperbolic / non-credible threat language',
          node: leaf(
            'harassment.threats.hyperbolic',
            'Hyperbolic threat language',
            'harassment',
            'mark'
          ),
        },
        {
          key: '3',
          label: 'Death wish / wishing harm',
          node: leaf(
            'harassment.threats.wish_harm',
            'Wishing harm / death wish',
            'harassment',
            'remove',
            { severity: 'severe' }
          ),
        },
      ]),
    },
    {
      key: '3',
      label: 'Unwanted sexual advances / solicitation',
      node: branch('harassment.sexual', 'What form?', [
        {
          key: '1',
          label: 'Unsolicited sexual messages toward a person',
          node: leaf(
            'harassment.sexual.unsolicited',
            'Unsolicited sexual advances',
            'harassment',
            'remove'
          ),
        },
        {
          key: '2',
          label: 'Sexual blackmail / coercion',
          node: branch(
            'harassment.sexual.blackmail_gate',
            'Does this involve a minor (sextortion of anyone under 18)?',
            [
              {
                key: '1',
                label: 'Yes — minor involved → escalate child safety',
                node: escalationChildSafety('mature'),
              },
              {
                key: '2',
                label: 'Adults only',
                node: leaf(
                  'harassment.sexual.blackmail',
                  'Sexual blackmail',
                  'harassment',
                  'remove',
                  { severity: 'severe' }
                ),
              },
            ]
          ),
        },
        {
          key: '3',
          label: 'Creepy but non-explicit interest',
          node: leaf(
            'harassment.sexual.creepy',
            'Creepy non-explicit interest',
            'harassment',
            'mark'
          ),
        },
      ]),
    },
    {
      key: '4',
      label: 'Stalking / repeated unwanted contact',
      node: branch(
        'harassment.stalking_gate',
        'Is there an imminent threat (swatting, showing up, weapons)?',
        [
          {
            key: '1',
            label: 'Yes — imminent → escalate',
            node: escalationImminentViolence('violence'),
          },
          {
            key: '2',
            label: 'Repeated unwanted contact, not imminent',
            node: leaf(
              'harassment.stalking',
              'Stalking / repeated unwanted contact',
              'harassment',
              'remove',
              { severity: 'severe' }
            ),
          },
        ]
      ),
    },
    {
      key: '5',
      label: 'Impersonation to harass',
      node: leaf(
        'harassment.impersonation',
        'Impersonation to harass',
        'harassment',
        'remove'
      ),
    },
  ]);
}

function hateTree(): PolicyNode {
  return branch('hate', 'What kind of hate speech?', [
    {
      key: '1',
      label: 'Attack on protected characteristic',
      node: branch('hate.protected', 'Which form?', [
        {
          key: '1',
          label: 'Dehumanizing language',
          node: leaf('hate.protected.dehumanizing', 'Dehumanizing hate', 'hate', 'remove', {
            severity: 'severe',
          }),
        },
        {
          key: '2',
          label: 'Slurs targeting a group',
          node: leaf('hate.protected.slurs', 'Group-targeted slurs', 'hate', 'remove', {
            severity: 'severe',
          }),
        },
        {
          key: '3',
          label: 'Calls for exclusion / segregation',
          node: leaf('hate.protected.exclusion', 'Calls for exclusion', 'hate', 'remove', {
            severity: 'severe',
            rationale: 'Meta Tier-1 style exclusion/segregation attacks',
          }),
        },
        {
          key: '4',
          label: 'Stereotypes without attack (borderline)',
          node: leaf('hate.protected.stereotype', 'Borderline stereotype', 'hate', 'mark'),
        },
      ]),
    },
    {
      key: '2',
      label: 'Praise of hate groups / atrocities',
      node: leaf('hate.praise', 'Praise of hate groups', 'hate', 'remove', {
        severity: 'severe',
      }),
    },
    {
      key: '3',
      label: 'Conspiracy theories targeting a group',
      node: leaf('hate.conspiracy', 'Group-targeted conspiracy', 'hate', 'remove'),
    },
    {
      key: '4',
      label: 'Reclaimed / in-group usage (context OK)',
      node: leaf('hate.reclaimed', 'Reclaimed in-group usage', 'hate', 'dismiss'),
    },
  ]);
}

function matureInnerTree(): PolicyNode {
  return branch('mature', 'What kind of mature content?', [
    {
      key: '1',
      label: 'Pornography / explicit sex',
      node: branch('mature.porn', 'How was it presented?', [
        {
          key: '1',
          label: 'Unlabeled explicit media',
          node: leaf('mature.porn.unlabeled', 'Unlabeled pornography', 'mature', 'remove'),
        },
        {
          key: '2',
          label: 'Labeled adult space / expected context',
          node: leaf(
            'mature.porn.labeled_space',
            'Labeled adult-context porn',
            'mature',
            'mark'
          ),
        },
        {
          key: '3',
          label: 'Animated / drawn explicit',
          node: leaf('mature.porn.animated', 'Animated explicit', 'mature', 'mark'),
        },
      ]),
    },
    {
      key: '2',
      label: 'Sexualization of minors (any)',
      // Prefer escalation.child_safety so training + account path share one leaf.
      node: escalationChildSafety('mature'),
    },
    {
      key: '3',
      label: 'Nudity (non-sexual / artistic)',
      node: branch('mature.nudity', 'Context?', [
        {
          key: '1',
          label: 'Sexualized nudity',
          node: leaf('mature.nudity.sexualized', 'Sexualized nudity', 'mature', 'mark'),
        },
        {
          key: '2',
          label: 'Artistic / educational / medical',
          node: leaf('mature.nudity.artistic', 'Artistic/educational nudity', 'mature', 'dismiss'),
        },
        {
          key: '3',
          label: 'Shock / unwanted exposure',
          node: leaf('mature.nudity.shock', 'Shock nudity', 'mature', 'remove'),
        },
      ]),
    },
    {
      key: '4',
      label: 'Fetish / kink (consensual adult)',
      node: leaf('mature.fetish', 'Adult fetish/kink', 'mature', 'mark'),
    },
    {
      key: '5',
      label: 'Suggestive but not explicit',
      node: leaf('mature.suggestive', 'Suggestive non-explicit', 'mature', 'mark'),
    },
    {
      key: '6',
      label: 'Auto-flag false positive (not sexual)',
      node: leaf(
        'mature.false_positive',
        'Mature auto-flag false positive',
        'mature',
        'dismiss'
      ),
    },
    {
      key: '7',
      label: 'Grooming / sexual solicitation of a minor',
      node: escalationChildSafety('mature'),
    },
    {
      key: '8',
      label: 'Child endangerment (non-sexual)',
      node: leaf(
        'mature.child_endangerment',
        'Non-sexual child endangerment',
        'mature',
        'remove',
        {
          severity: 'severe',
          rationale: 'Dangerous challenges, trafficking facilitation, physical abuse of minors',
        }
      ),
    },
  ]);
}

/** Mature path always asks the child-safety gate first (platform pattern). */
function matureTree(): PolicyNode {
  return branch(
    'mature.gate',
    'Does this involve sexual content with a minor (real, AI, drawn, or grooming)?',
    [
      {
        key: '1',
        label: 'Yes — child sexual exploitation → escalate',
        node: escalationChildSafety('mature'),
      },
      {
        key: '2',
        label: 'No — adults only / non-sexual',
        node: matureInnerTree(),
      },
    ]
  );
}

function violenceTree(): PolicyNode {
  return branch('violence', 'What kind of violence content?', [
    {
      key: '1',
      label: 'Real-world graphic gore',
      node: leaf('violence.gore', 'Graphic gore', 'violence', 'remove', {
        severity: 'severe',
      }),
    },
    {
      key: '2',
      label: 'Animal cruelty',
      node: leaf('violence.animal', 'Animal cruelty', 'violence', 'remove', {
        severity: 'severe',
      }),
    },
    {
      key: '3',
      label: 'Incitement to violent crime',
      node: leaf('violence.incitement', 'Incitement to violence', 'violence', 'remove', {
        severity: 'severe',
      }),
    },
    {
      key: '4',
      label: 'Fictional / game violence',
      node: leaf('violence.fictional', 'Fictional violence', 'violence', 'dismiss'),
    },
    {
      key: '5',
      label: 'News / documentary graphic (labeled)',
      node: leaf('violence.news', 'News/documentary graphic', 'violence', 'mark'),
    },
  ]);
}

/**
 * Standalone Step-2 category (Meta DOI / YouTube VCO / TikTok / Discord / X).
 * Graphic violence without a terror nexus stays under Violence.
 */
function terrorismTree(): PolicyNode {
  return branch('terrorism', 'What kind of terrorism-related content?', [
    {
      key: '1',
      label: 'Recruitment / fundraising / operational planning',
      node: leaf(
        'terrorism.ops',
        'Terrorist recruitment or operational planning',
        'terrorism',
        'remove',
        {
          severity: 'severe',
          rationale: 'Active material support / ops — remove + instant account review',
        }
      ),
    },
    {
      key: '2',
      label: 'Praise / propaganda for a terrorist org or attack',
      node: leaf(
        'terrorism.praise',
        'Terrorist praise or propaganda',
        'terrorism',
        'remove',
        {
          severity: 'severe',
          rationale: 'Glorifying terrorist entities or attacks',
        }
      ),
    },
    {
      key: '3',
      label: 'Threat to commit a terrorist attack',
      node: branch(
        'terrorism.threat_gate',
        'Is the threat specific and imminent?',
        [
          {
            key: '1',
            label: 'Yes — imminent → escalate',
            node: escalationImminentViolence('terrorism'),
          },
          {
            key: '2',
            label: 'Threat without clear imminence',
            node: leaf(
              'terrorism.threat',
              'Terrorist attack threat',
              'terrorism',
              'remove',
              { severity: 'severe' }
            ),
          },
        ]
      ),
    },
    {
      key: '4',
      label: 'News / documentary / condemnation (no praise)',
      node: leaf(
        'terrorism.news',
        'Terrorism news or condemnation',
        'terrorism',
        'mark',
        {
          rationale: 'Public-interest reporting or clear condemnation — mark, do not remove',
        }
      ),
    },
    {
      key: '5',
      label: 'Historical / educational without glorification',
      node: leaf(
        'terrorism.historical',
        'Historical or educational terrorism discussion',
        'terrorism',
        'dismiss',
        { rationale: 'Context is educational or historical, not praise' }
      ),
    },
  ]);
}

function selfHarmTree(): PolicyNode {
  return branch(
    'self_harm.gate',
    'Is this an active suicide / self-harm crisis with a concrete plan?',
    [
      {
        key: '1',
        label: 'Yes — imminent plan → escalate',
        node: escalationSuicideCrisis(),
      },
      {
        key: '2',
        label: 'No — other self-harm content',
        node: branch('self_harm', 'What kind of self-harm content?', [
          {
            key: '1',
            label: 'Promotion / instruction',
            node: leaf('self_harm.promotion', 'Self-harm promotion', 'self_harm', 'remove', {
              severity: 'severe',
            }),
          },
          {
            key: '2',
            label: 'Graphic self-harm imagery',
            node: leaf('self_harm.graphic', 'Graphic self-harm imagery', 'self_harm', 'remove'),
          },
          {
            key: '3',
            label: 'Suicidal ideation seeking help',
            node: leaf(
              'self_harm.ideation_help',
              'Ideation seeking help',
              'self_harm',
              'mark',
              { rationale: 'Keep for help resources; do not amplify' }
            ),
          },
          {
            key: '4',
            label: 'Recovery / awareness (non-graphic)',
            node: leaf('self_harm.recovery', 'Recovery/awareness', 'self_harm', 'dismiss'),
          },
          {
            key: '5',
            label: 'Disordered eating / dangerous weight methods (promo)',
            node: leaf(
              'self_harm.eating_disorder',
              'Disordered eating promotion',
              'self_harm',
              'remove',
              {
                rationale: 'TikTok / YouTube / Meta — tips or praise for disordered eating',
              }
            ),
          },
        ]),
      },
    ]
  );
}

function misinfoTree(): PolicyNode {
  return branch('misinfo', 'What kind of misinformation?', [
    {
      key: '1',
      label: 'Health / medical falsehood with harm risk',
      node: leaf('misinfo.health_harm', 'Harmful health misinfo', 'misinfo', 'remove'),
    },
    {
      key: '2',
      label: 'Election / civic process falsehood',
      node: leaf('misinfo.civic', 'Civic/election misinfo', 'misinfo', 'mark'),
    },
    {
      key: '3',
      label: 'Manipulated media presented as real',
      node: leaf('misinfo.manipulated', 'Manipulated media as real', 'misinfo', 'remove'),
    },
    {
      key: '4',
      label: 'Opinion / satire clearly labeled',
      node: leaf('misinfo.satire', 'Labeled satire/opinion', 'misinfo', 'dismiss'),
    },
    {
      key: '5',
      label: 'Unverified claim (low harm)',
      node: leaf('misinfo.low_harm', 'Low-harm unverified claim', 'misinfo', 'mark'),
    },
    {
      key: '6',
      label: 'Crisis / disaster panic hoax',
      node: leaf(
        'misinfo.crisis_panic',
        'Crisis or disaster panic hoax',
        'misinfo',
        'remove',
        {
          rationale: 'TikTok / Discord — false claims that can cause public panic or harm',
        }
      ),
    },
  ]);
}

function scamTree(): PolicyNode {
  return branch('scam', 'What kind of scam?', [
    {
      key: '1',
      label: 'Financial fraud / fake giveaway',
      node: leaf('scam.financial', 'Financial fraud', 'scam', 'remove', {
        severity: 'severe',
      }),
    },
    {
      key: '2',
      label: 'Impersonation of Matterya / brands',
      node: leaf('scam.impersonation', 'Brand impersonation scam', 'scam', 'remove', {
        severity: 'severe',
      }),
    },
    {
      key: '3',
      label: 'Romance / social engineering',
      node: leaf('scam.romance', 'Romance/social engineering', 'scam', 'remove', {
        severity: 'severe',
        rationale: 'Financial + emotional harm — escalate like other fraud',
      }),
    },
    {
      key: '4',
      label: 'Suspicious but unclear',
      node: leaf('scam.unclear', 'Suspicious unclear', 'scam', 'mark'),
    },
    {
      key: '5',
      label: 'Sale of weapons / drugs / regulated goods',
      node: leaf(
        'scam.regulated_goods',
        'Regulated or dangerous goods for sale',
        'scam',
        'remove',
        {
          severity: 'severe',
          rationale: 'YouTube / Discord / TikTok / Meta restricted goods',
        }
      ),
    },
  ]);
}

function doxxingTree(): PolicyNode {
  return branch('doxxing', 'What privacy violation?', [
    {
      key: '1',
      label: 'Home address / phone / ID documents',
      node: branch(
        'doxxing.pii_gate',
        'Is this tied to imminent harm (swatting, stalking, “I know where you live” with a plan)?',
        [
          {
            key: '1',
            label: 'Yes — imminent → escalate',
            node: escalationImminentViolence('violence'),
          },
          {
            key: '2',
            label: 'PII exposure without imminent plan',
            node: leaf('doxxing.pii_hard', 'Hard PII exposure', 'doxxing', 'remove', {
              severity: 'severe',
            }),
          },
        ]
      ),
    },
    {
      key: '2',
      label: 'NCII — intimate images / private messages without consent',
      node: branch(
        'doxxing.intimate_gate',
        'Does the NCII involve a minor?',
        [
          {
            key: '1',
            label: 'Yes — minor → escalate child safety',
            node: escalationChildSafety('mature'),
          },
          {
            key: '2',
            label: 'Adult NCII',
            node: leaf(
              'doxxing.intimate',
              'Non-consensual intimate imagery (NCII)',
              'doxxing',
              'remove',
              {
                severity: 'severe',
                rationale:
                  'X / Discord / Meta / Snap — NCII including AI-generated of real people',
              }
            ),
          },
        ]
      ),
    },
    {
      key: '3',
      label: 'Workplace / school identifying info to harass',
      node: leaf('doxxing.workplace', 'Workplace/school doxx', 'doxxing', 'remove', {
        severity: 'severe',
      }),
    },
    {
      key: '4',
      label: 'Publicly known info (news, official pages)',
      node: leaf('doxxing.public_record', 'Public-record info', 'doxxing', 'dismiss'),
    },
  ]);
}

const LEAF_INDEX = new Map<string, PolicyLeaf>();

function indexNode(node: PolicyNode): void {
  if (node.kind === 'leaf') {
    LEAF_INDEX.set(node.id, node);
    return;
  }
  for (const opt of node.options) indexNode(opt.node);
}

indexNode(POLICY_TREE);

export function getPolicyLeaf(id: string): PolicyLeaf | null {
  return LEAF_INDEX.get(String(id || '').trim()) ?? null;
}

export function listPolicyLeaves(): PolicyLeaf[] {
  return [...LEAF_INDEX.values()];
}

/** Client-safe tree: questions/options only — no outcomes. */
export function policyTreeForClient(node: PolicyNode = POLICY_TREE): unknown {
  if (node.kind === 'leaf') {
    return { kind: 'leaf', id: node.id, label: node.label };
  }
  return {
    kind: 'branch',
    id: node.id,
    question: node.question,
    options: node.options.map((o) => ({
      key: o.key,
      label: o.label,
      node: policyTreeForClient(o.node),
    })),
  };
}

export function outcomeToResolveAction(
  outcome: PolicyOutcome
): 'remove' | 'mark' | 'skip' {
  if (outcome === 'remove') return 'remove';
  if (outcome === 'mark') return 'mark';
  return 'skip';
}

export function leafSeverity(leaf: PolicyLeaf): 'mild' | 'severe' {
  if (leaf.outcome !== 'remove') return 'mild';
  return leaf.severity === 'severe' ? 'severe' : 'mild';
}
