export type Audience =
  | 'voter'
  | 'politician'
  | 'media'
  | 'aiLab'
  | 'partnership'
  | 'careers'
  | 'support'

const map: Record<Audience, string | undefined> = {
  voter: import.meta.env.PUBLIC_VOTER_FORM_ENDPOINT,
  politician: import.meta.env.PUBLIC_POLITICIAN_FORM_ENDPOINT,
  media: import.meta.env.PUBLIC_MEDIA_FORM_ENDPOINT,
  aiLab: import.meta.env.PUBLIC_AI_LAB_FORM_ENDPOINT,
  partnership: import.meta.env.PUBLIC_PARTNERSHIP_FORM_ENDPOINT,
  careers: import.meta.env.PUBLIC_CAREERS_FORM_ENDPOINT,
  support: import.meta.env.PUBLIC_SUPPORT_FORM_ENDPOINT,
}

const envName: Record<Audience, string> = {
  voter: 'PUBLIC_VOTER_FORM_ENDPOINT',
  politician: 'PUBLIC_POLITICIAN_FORM_ENDPOINT',
  media: 'PUBLIC_MEDIA_FORM_ENDPOINT',
  aiLab: 'PUBLIC_AI_LAB_FORM_ENDPOINT',
  partnership: 'PUBLIC_PARTNERSHIP_FORM_ENDPOINT',
  careers: 'PUBLIC_CAREERS_FORM_ENDPOINT',
  support: 'PUBLIC_SUPPORT_FORM_ENDPOINT',
}

export function getFormEndpoint(audience: Audience): string {
  const url = map[audience]
  if (!url) {
    throw new Error(
      `Form endpoint for "${audience}" is not configured. Set ${envName[audience]} in your environment.`,
    )
  }
  return url
}
