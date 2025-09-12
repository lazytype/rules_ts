export type Identity<T> = T

export type MergeIntersectionTypes<T> = Identity<{ [K in keyof T]: T[K] }>
