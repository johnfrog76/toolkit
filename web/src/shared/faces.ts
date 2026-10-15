export interface FaceConfig {
  content: string;
  fontSize: string;
  rotate: string;
  top: string;
  left: string;
}

export interface Face {
  id: string;
  name: string;
  light: FaceConfig;
  dark: FaceConfig;
}

export const FACES: Face[] = [
  {
    id: "smile",
    name: "Classic",
    light: { content: ")", fontSize: "54%", rotate: "90deg", top: "18px", left: "31px" },
    dark: { content: ")", fontSize: "54%", rotate: "90deg", top: "18px", left: "31px" },
  },
  {
    id: "curly",
    name: "Fancy",
    light: { content: "{", fontSize: "81%", rotate: "97deg", top: "19px", left: "27px" },
    dark: { content: "{", fontSize: "81%", rotate: "97deg", top: "19px", left: "27px" },
  },
  {
    id: "squiggle",
    name: "Dizzy",
    light: { content: "~", fontSize: "90%", rotate: "15deg", top: "16px", left: "28px" },
    dark: { content: "~", fontSize: "90%", rotate: "-15deg", top: "16px", left: "28px" },
  },
  {
    id: "cat",
    name: "Kitty",
    light: { content: "ω", fontSize: "55%", rotate: "0deg", top: "20px", left: "27px" },
    dark: { content: "ω", fontSize: "55%", rotate: "0deg", top: "20px", left: "27px" },
  },
  {
    id: "gasp",
    name: "Shocked",
    light: { content: "o", fontSize: "55%", rotate: "0deg", top: "20px", left: "29px" },
    dark: { content: "O", fontSize: "50%", rotate: "0deg", top: "21px", left: "29px" },
  },
  {
    id: "smirk",
    name: "Sly",
    light: { content: ">", fontSize: "65%", rotate: "90deg", top: "17px", left: "30px" },
    dark: { content: ">", fontSize: "65%", rotate: "90deg", top: "17px", left: "30px" },
  },
  {
    id: "wink",
    name: "Cheeky",
    light: { content: ";", fontSize: "54%", rotate: "90deg", top: "18px", left: "31px" },
    dark: { content: ";", fontSize: "54%", rotate: "90deg", top: "18px", left: "31px" },
  },
  {
    id: "flat",
    name: "Stoic",
    light: { content: "—", fontSize: "65%", rotate: "0deg", top: "21px", left: "22px" },
    dark: { content: "━", fontSize: "65%", rotate: "0deg", top: "21px", left: "22px" },
  },
  {
    id: "kiss",
    name: "Smooch",
    light: { content: "3", fontSize: "55%", rotate: "0deg", top: "19px", left: "29px" },
    dark: { content: "3", fontSize: "55%", rotate: "0deg", top: "19px", left: "29px" },
  },
  {
    id: "sharp",
    name: "Edge",
    light: { content: "V", fontSize: "55%", rotate: "0deg", top: "20px", left: "29px" },
    dark: { content: "V", fontSize: "55%", rotate: "0deg", top: "20px", left: "29px" },
  },
  {
    id: "wave",
    name: "Groovy",
    light: { content: "S", fontSize: "55%", rotate: "0deg", top: "19px", left: "29px" },
    dark: { content: "S", fontSize: "55%", rotate: "0deg", top: "19px", left: "29px" },
  },
  {
    id: "square",
    name: "Boxy",
    light: { content: "□", fontSize: "45%", rotate: "0deg", top: "20px", left: "28px" },
    dark: { content: "■", fontSize: "45%", rotate: "0deg", top: "20px", left: "28px" },
  },
];

export const DEFAULT_FACE_ID = "smile";
