/**
 * Zen Word Scrape's dictionary and its rules (D-L21, from the owner's hub note): a bundled list of calm, positive words --
 * drafted by Claude for the owner's edit -- and the two questions the
 * card asks of it: which words a ring's letters can make, and which words are
 * fit to BE a ring (five or six letters, and enough other words inside them
 * that the ring is worth sitting with).
 *
 * No network, no score, no streak: a list in the bundle and a handful of
 * pure functions, so the card is the same on every machine and asks nothing.
 */

const DRAFT = `
ace air arc art awe ape bay bee cap car cat cup dew ear eat elm era eve fig fir gem hat hay hen hue
ice ink ivy jam jar joy key kin lap lea lee log mat nap net oak oar oat one ore pat pea pen pet pie
pin ram rat ray red rim rye sap sea set sip sit sky sun tan tar tea tee ten tie tin toe top use van
yes zen ale arm ash bun den dot elf eel emu fan fen fog fox gin gum ham hop hum ivy jet lit map nod
nut orb owl pad pal paw ram rug sew tap tug tub urn wax yew yam aloe arch aria balm barn bath beam
bean bear bell bird blue boat calm cape care cart cast chai coat cove cozy crop dawn deer dove dune
dusk earn ease east echo fern fire fish glow gold halo harp haze heal heat herb hill home hope hour
isle kind kite lake lamp lark lawn leaf lime lily love mild mint mist moon moss muse nest nice note
oath opal palm pace pare park path pear peat pine plum pond pool pure rain rare real reed rest ring
rise rock rose sage sail salt sand seal seat seed silk snow soft song star stem tale tame team tide
tone tree true tune vale vase warm wave wind wing wish wood wool yard zest hear dare read dear tear
rate tare near earn mane name amen mean lane lean neat nose eons ones tens sent tent toes cane acne
cent race acre dean gear rage grad drag garb bare beam mane amber aroma bloom brook cabin cedar
charm cheer clear cloud coral cream creek daisy dream drift earth ember fresh glade grace grain
grape grass green grove haven heart honey karma lemon light lilac linen lotus lunar maple marsh
merry ocean olive orbit peace peach pearl petal piano plain plush quiet quilt relax river robin
shade shell shine shore slate sleep smile spice still stone sunny sweet tempo thyme tidal trail
tulip water wheat whale woven steam tames mates meats seats tastes notes tones onset stole breeze
bright candle canopy cotton garden gentle ginger harbor hearth kindly lagoon meadow mellow nature
orchid pebble pillow planet repose serene silver simple sorbet spring stream summer sunset temple
tender thanks violet walnut willow winter wonder yellow ate met tam mast teas seam meat mate same
eats seat east team tame stem mats sets tabs bats stab cab cat act arc car ram arm mar tar rat art
hat bat tab ant tan nab ban bar bra raw war jaw jam bad dab dad add ado odd dot tod toe toy yet eye
bye yes she hem him his hit tie tin nit dip pit tip pot top opt tot tap pat apt sap asp spa pas gap
nag gag gab bag bug gum mug hug jug tug rug dug dog god cog log fog bog hog jog nod don dun nun sun
run urn bun nub tub but tut cut cup pup pun nap pan pad dip lid lip pip sip sit its tin ink kin kit
tick tock lock lake leak kale elk lea ale lap pal alp all ill sill still list silt lit tilt slit
slot lots lost toss cost cot cots cob bob orb rob mob bop fob job jot jut nut tun ton not knot tone
note tote toe owe woe woo two tow own now won snow sown owns worn word rows sow sew wed dew wet stew
west vest vet veto vote dove doe ode nod den end lend bend mend send tend dent net ten tent nest
sent sane vane nave even vine vein veil evil live vile lie lei tie tile lite lint tint mint stint
nits snit sin sit sits sift fist fit fig gift lift felt left elf flee feel fee reef free fern fen
hen when then than tan ant aunt tuna nut nuts stun suns snug sung gun gnu gust gut tug hut hue hum
hem helm elm melt tel let lets lest jest jet jets test sets pest pets step pets spot pots stop tops
post opts spit pits tips pity type typo pot poet toe rope pore pour our sour ours rose sore ore roe
orbs bore robe boar oar oat oats taro rota rat tar art tart star stars tsar rats arts sat sap tap
pat apt part trap tarp rap par pear reap pare rape ape pea pace cape ace race care acre arc car scar
cars arcs tacos coat taco cot cat act oat atom moat mat tam ma am me em he eh ho oh so os us up mile
lime slim slip lips pals slap laps alps plan clan lance clean lane lean deal dale lead lad ideal
idle dial laid dial mail mile lame male meal elm mole moles lemons melon lemon omen omens mens stem
mesh hems hemp temp tempt empty type step pest pets rain ran air rein rain rani rains stain saint
satin tins nits stair astir sitar hearts earths haste hates heats hat heat eat tea ate the she sea
seat eats teas east loves solve vole voles love lose sole loves shoe hose hoes shoes those ethos
shot host hots share hears shear rash hares hear hare ash has sash cash chase aches each ache grape
pager gape page rage gear rag age pea gap peg ape grapes pages apes reap pearl paler pale leap plea
pare rape rap lap alp real earl era ear ale lea are pear wheat thaw what heat hate wet tea eat ate
haw awe wan tan hat the coral carol oral car oar arc cola coal a cloud could clod cold loud old cud
duo out water tear rate wear ware await wart raw tar art ate tea eat awe war wet light lit hit tilt
gilt stone notes onset tones tone note ones nose eons sent nest ten net set toe not ton one son
`;

/** Every word, once, lowercase, letters only, three letters or more. */
export const WORDS: readonly string[] = Array.from(
  new Set(
    DRAFT.split(/\s+/)
      .map((w) => w.trim().toLowerCase())
      .filter((w) => /^[a-z]{3,}$/.test(w)),
  ),
).sort();

const WORD_SET = new Set(WORDS);

export function isWord(w: string): boolean {
  return WORD_SET.has(w);
}

/** Can `word` be spelled from `letters`, each letter used at most as often
 *  as it appears? */
export function canMake(word: string, letters: string): boolean {
  const pool = new Map<string, number>();
  for (const ch of letters) pool.set(ch, (pool.get(ch) ?? 0) + 1);
  for (const ch of word) {
    const left = pool.get(ch) ?? 0;
    if (left === 0) return false;
    pool.set(ch, left - 1);
  }
  return true;
}

/** Every list word a ring's letters can make, the ring's own word included. */
export function wordsFrom(letters: string): string[] {
  return WORDS.filter((w) => canMake(w, letters));
}

/** How many OTHER words a ring must hold to be worth sitting with. */
export const RING_MIN_OTHERS = 3;

/** The words fit to be a ring: five or six letters, with enough inside. */
export const RING_WORDS: readonly string[] = WORDS.filter(
  (w) => (w.length === 5 || w.length === 6) && wordsFrom(w).length - 1 >= RING_MIN_OTHERS,
);

/** A ring that is not `exclude`, chosen by chance; the letters shuffled so
 *  the word is not simply read off the ring. */
export function nextRing(
  exclude?: string,
  random: () => number = Math.random,
): { ring: string; letters: string } {
  const pool = RING_WORDS.filter((w) => w !== exclude);
  const ring = pool[Math.floor(random() * pool.length)] ?? RING_WORDS[0];
  const chars = ring.split("");
  for (let i = chars.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return { ring, letters: chars.join("") };
}
