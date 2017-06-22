-- | Cursors into byte-addressed memory that allow type-safe writing
-- and reading of serialized data.
-- 
-- Requires the "linear-types" branch of GHC from the tweag.io fork.

{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE ViewPatterns #-}

module Cursors.Mutable
    ( -- * Cursors, with their implementation revealed:
      Has(..), Needs(..), Packed
      -- * Public cursor interface
    , writeC, readC, fromHas, toHas
    , finish, withOutput

      -- * Unsafe interface
    , unsafeCastNeeds
    )
    where      

import Linear.Std
import qualified ByteArray as ByteArray

import Data.ByteString (ByteString)
import qualified Data.ByteString as ByteString
import Data.Monoid
import Data.Word
import Data.Int
import Foreign.Storable
import Prelude hiding (($))

-- Hard-coded constant:
--------------------------------------------------------------------------------
-- | Size allocated for each regions: 4KB.
regionSize :: Int
regionSize = 4096 -- in Bytes

-- Cursor Types:
--------------------------------------------------------------------------------

-- | A "needs" cursor requires a list of fields be written to the
-- bytestream before the data is fully initialized.  Once it is, a
-- value of the (second) type parameter can be extracted.
newtype Needs (l :: [*]) t = Needs ByteArray.WByteArray

-- | A "has" cursor is a pointer to a series of consecutive,
-- serialized values.  It can be read multiple times.
newtype Has (l :: [*]) = Has ByteString
  deriving Show

-- | A packed value is very like a singleton Has cursor.  It
-- represents a dense encoding of a single value of the type `a`.
newtype Packed a = Packed ByteString
  deriving (Show,Eq)


-- Cursor interface
--------------------------------------------------------------------------------
         
-- | Write a value to the cursor.  Write doesn't need to be linear in
-- the value written, because that value is serialized and copied.
writeC :: Storable a => a -> Needs (a ': rst) t ⊸ Needs rst t
writeC a (Needs bld1) = Needs (ByteArray.writeStorable a bld1)

-- | Reading from a cursor scrolls past the read item and gives a
-- cursor into the next element in the stream:
readC :: Storable a => Has (a ': rst) -> (a, Has rst)
readC (Has bs) = (a, Has (ByteString.drop (sizeOf a) bs))
  where
    a = ByteArray.headStorable bs

-- | Safely "cast" a has-cursor to a packed value.
fromHas :: Has '[a] ⊸ Packed a
fromHas (Has b) = Packed b

-- | Safely cast a packed value to a has cursor.
toHas :: Packed a ⊸ Has '[a]
toHas (Packed b) = Has b

-- | Perform an unsafe conversion reflecting knowledge about the
-- memory layout of a particular type (when packed).
unsafeCastNeeds :: Needs l1 a ⊸ Needs l2 a
unsafeCastNeeds (Needs b) = (Needs b)


-- | "Cast" a fully-initialized write cursor into a read one.
finish :: Needs '[] a ⊸ Unrestricted (Has '[a])
finish (Needs bs) = Has `mapU` ByteArray.freeze bs

-- | Allocate a fresh output cursor and compute with it.
withOutput :: (Needs '[a] a ⊸ Unrestricted b) ⊸ Unrestricted b
withOutput fn = ByteArray.alloc regionSize $ \ bs -> fn (Needs bs)

-- Tests:
--------------------------------------------------------------------------------

foo :: Needs '[Int, Bool] Double
foo = undefined

bar :: Needs '[Bool] Double
bar = writeC 3 foo

test01 :: Needs '[Int] a ⊸ Needs '[] a
test01 x = writeC 3 x

test02 :: Needs '[] Double
test02 = writeC True bar

test03 :: Double
test03 = fst (readC (getUnrestricted (finish test02)))
