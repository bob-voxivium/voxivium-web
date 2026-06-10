import { z } from 'zod'

const nameRegex = /^[\p{L}\s'-]+$/u

export const voterSignupSchema = z.object({
  firstName: z
    .string()
    .trim()
    .min(1, 'First name is required.')
    .max(24, 'Please keep your first name under 25 characters.')
    .regex(nameRegex, 'Letters, spaces, apostrophes and hyphens only.'),
  email: z.string().trim().email('Please enter a valid email address.'),
  state: z.string().trim().min(2, 'Please choose your state.'),
})
export type VoterSignup = z.infer<typeof voterSignupSchema>

export const politicianContactSchema = z.object({
  firstName: z.string().trim().min(1).max(48),
  lastName: z.string().trim().min(1).max(48),
  email: z.string().trim().email(),
  office: z.string().trim().min(1).max(120),
  jurisdiction: z.string().trim().min(1).max(120),
  message: z.string().trim().max(2000).optional(),
})
export type PoliticianContact = z.infer<typeof politicianContactSchema>

export const mediaContactSchema = z.object({
  name: z.string().trim().min(1).max(96),
  email: z.string().trim().email(),
  organization: z.string().trim().min(1).max(120),
  role: z.string().trim().min(1).max(120),
  useCase: z.string().trim().min(1).max(2000),
  message: z.string().trim().max(2000).optional(),
})
export type MediaContact = z.infer<typeof mediaContactSchema>

export const aiLabContactSchema = z.object({
  name: z.string().trim().min(1).max(96),
  email: z.string().trim().email(),
  organization: z.string().trim().min(1).max(120),
  useCase: z.string().trim().min(1).max(2000),
  scale: z.string().trim().min(1).max(120),
})
export type AiLabContact = z.infer<typeof aiLabContactSchema>

export const RESUME_MAX_BYTES = 2 * 1024 * 1024

export const careersPositionSchema = z.enum([
  'Support, QA, and Deployment Engineer',
  'Marketing, Pricing, and Sales',
  'Policy & Content Specialist',
  'Other',
])
export type CareersPosition = z.infer<typeof careersPositionSchema>

export const careersApplicationSchema = z.object({
  firstName: z.string().trim().min(1).max(48),
  lastName: z.string().trim().min(1).max(48),
  email: z.string().trim().email(),
  phone: z.string().trim().max(40).optional(),
  position: careersPositionSchema,
  linkedin: z
    .string()
    .trim()
    .url('Please enter a valid LinkedIn or personal site URL.')
    .max(300)
    .optional(),
  message: z.string().trim().max(2000).optional(),
  resume: z
    .instanceof(File, { message: 'Please attach your resume as a PDF.' })
    .refine((f) => f.size > 0, 'Please attach a resume.')
    .refine(
      (f) => f.size <= RESUME_MAX_BYTES,
      'Resume must be 2 MB or smaller. Please re-export or compress your file.',
    )
    .refine((f) => f.type === 'application/pdf', 'Please attach a PDF file.'),
})
export type CareersApplication = z.infer<typeof careersApplicationSchema>

export const partnershipInquirySchema = z.object({
  name: z.string().trim().min(1).max(96),
  email: z.string().trim().email(),
  organization: z.string().trim().min(1).max(120),
  role: z.string().trim().max(120).optional(),
  interest: z.string().trim().min(1).max(2000),
  message: z.string().trim().max(2000).optional(),
})
export type PartnershipInquiry = z.infer<typeof partnershipInquirySchema>
