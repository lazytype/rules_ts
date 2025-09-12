import { type MergeIntersectionTypes } from 'shared/types/utils'

export type Bar = MergeIntersectionTypes<{ a: 1 } & { b: 2 }>
