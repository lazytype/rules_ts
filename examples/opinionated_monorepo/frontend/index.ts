import { type MergeIntersectionTypes } from 'shared/types/utils'

export type Foo = MergeIntersectionTypes<{ a: 1 } & { b: 2 }>
