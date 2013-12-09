{-# Language FunctionalDependencies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# Language GADTs #-}
{-# Language TemplateHaskell #-}
{-# Language ViewPatterns #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ForeignFunctionInterface #-}
module Test.FunPtr
  ( tests )
  where

import H.Prelude
import qualified H.Internal.FunWrappers as H
import qualified Foreign.R as R
import qualified Language.R as R (withProtected, r2)

import Test.Tasty hiding (defaultMain)
import Test.Tasty.HUnit

import Control.Applicative
import Control.Concurrent.MVar
import Control.Monad
import Data.ByteString.Char8
import Foreign hiding (unsafePerformIO)
import System.IO.Unsafe (unsafePerformIO)
import System.Mem.Weak
import System.Mem

data HaveWeak a b = HaveWeak
       (R.SEXP a->IO (R.SEXP b))
       (MVar (Weak (FunPtr (R.SEXP a->IO (R.SEXP b)))))

foreign import ccall "missing_r.h funPtrToSEXP" funPtrToSEXP
    :: FunPtr () -> IO (R.SEXP R.Any)

instance Literal (HaveWeak a b) R.ExtPtr where
  mkSEXP (HaveWeak a box) = unsafePerformIO $ do
      z <- H.wrap1 a
      putMVar box =<< mkWeakPtr z Nothing
      fmap castPtr . funPtrToSEXP . castFunPtr $ z
  fromSEXP = error "not now"

tests :: TestTree
tests = testGroup "Tests" 
  [ testCase "funptr is freed from R" $ do
      ((Nothing @=?) =<<) $ do
         hwr <- HaveWeak return <$> newEmptyMVar
         _ <- alloca $ \p -> do
           e <- peek R.globalEnv
           _ <- R.withProtected (return $ mkSEXP hwr) $
             \sf -> R.tryEval (R.r2 (Data.ByteString.Char8.pack ".Call") sf (mkSEXP (2::Double))) e p
           replicateM_ 10 (R.allocVector R.Real 1024)
           replicateM_ 10 R.gc
         replicateM_ 10 performGC
         (\(HaveWeak _ x) -> takeMVar x >>= deRefWeak) hwr
  ]