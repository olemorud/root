// @(#)root/base:$Name:  $:$Id: TBits.cxx,v 1.13 2004/01/06 16:49:01 brun Exp $
// Author: Philippe Canal 05/02/2001
//    Feb  5 2001: Creation
//    Feb  6 2001: Changed all int to unsigned int.
//______________________________________________________________________________

//////////////////////////////////////////////////////////////////////////
//                                                                      //
// TBits                                                                //
//                                                                      //
// Container of bits                                                    //
//                                                                      //
// This class provides a simple container of bits.                      //
// Each bit can be set and tested via the functions SetBitNumber and    //
// TestBitNumber.                                             .         //
// The default value of all bits is kFALSE.                             //
// The size of the container is automatically extended when a bit       //
// number is either set or tested.  To reduce the memory size of the    //
// container use the Compact function, this will discard the memory     //
// occupied by the upper bits that are 0.                               //
//                                                                      //
//////////////////////////////////////////////////////////////////////////

#include "TBits.h"
#include "string.h"

ClassImp(TBits)

//______________________________________________________________________________
TBits::TBits(UInt_t nbits) : fNbits(nbits)
{
   // TBits constructor.  All bits set to 0

   if (nbits <= 0) nbits = 8;
   fNbytes  = ((nbits-1)/8) + 1;
   fAllBits = new UChar_t[fNbytes];
   // this is redundant only with libNew
   memset(fAllBits,0,fNbytes);
}

//______________________________________________________________________________
TBits::TBits(const TBits &original) : TObject(original), fNbits(original.fNbits),
   fNbytes(original.fNbytes)
{
   // TBits copy constructor

   fAllBits = new UChar_t[fNbytes];
   memcpy(fAllBits,original.fAllBits,fNbytes);

}

//______________________________________________________________________________
TBits& TBits::operator=(const TBits& rhs)
{
   // TBits assignment operator

   if (this != &rhs) {
      TObject::operator=(rhs);
      fNbits   = rhs.fNbits;
      fNbytes  = rhs.fNbytes;
      delete [] fAllBits;
      if (fNbytes != 0) {
         fAllBits = new UChar_t[fNbytes];
         memcpy(fAllBits,rhs.fAllBits,fNbytes);
      } else {
         fAllBits = 0;
      }
   }
   return *this;
}

//______________________________________________________________________________
TBits::~TBits()
{
   // TBits destructor

   delete [] fAllBits;
}

//______________________________________________________________________________
void TBits::Clear(Option_t * /*option*/)
{
   delete [] fAllBits;
   fAllBits = 0;
   fNbits   = 0;
   fNbytes  = 0;
}

//______________________________________________________________________________
void TBits::Compact()
{
   // Reduce the storage used by the object to a minimun

   if (!fNbits || !fAllBits) return;
   UInt_t needed;
   for(needed=fNbytes-1;
       needed > 0 && fAllBits[needed]==0; ) { needed--; };
   needed++;

   if (needed!=fNbytes) {
      UChar_t *old_location = fAllBits;
      fAllBits = new UChar_t[needed];

      memcpy(fAllBits,old_location,needed);
      delete [] old_location;

      fNbytes = needed;
      fNbits = 8*fNbytes;
   }
}

//______________________________________________________________________________
UInt_t TBits::CountBits(UInt_t startBit) const
{
   // Return number of bits set to 1 starting at bit startBit

   const Int_t nbits[256] = {
             0,1,1,2,1,2,2,3,1,2,2,3,2,3,3,4,
             1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,
             1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,
             2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
             1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,
             2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
             2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
             3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
             1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,
             2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
             2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
             3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
             2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
             3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
             3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
             4,5,5,6,5,6,6,7,5,6,6,7,6,7,7,8};

   UInt_t i,count = 0;
   if (startBit == 0) {
      for(i=0; i<fNbytes; i++) {
         count += nbits[fAllBits[i]];
      }
      return count;
   }
   if (startBit >= fNbits) return count;
   UInt_t startByte = startBit/8;
   UInt_t ibit = startBit%8;
   if (ibit) {
      for (i=ibit;i<8;i++) {
         if (fAllBits[startByte] & (1<<ibit)) count++;
      }
      startByte++;
   }
   for(i=startByte; i<fNbytes; i++) {
      count += nbits[fAllBits[i]];
   }
   return count;
}

//______________________________________________________________________________
UInt_t TBits::FirstNullBit(UInt_t startBit) const
{
   // Return position of first null bit

   const Int_t fbits[256] = {
             0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,
             0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,5,
             0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,
             0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,6,
             0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,
             0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,5,
             0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,
             0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,7,
             0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,
             0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,5,
             0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,
             0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,6,
             0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,
             0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,5,
             0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,
             0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,8};

   UInt_t i;
   if (startBit == 0) {
      for(UInt_t i=0; i<fNbytes; i++) {
         if (fAllBits[i] != 255) return 8*i + fbits[fAllBits[i]];
      }
      return fNbits;
   }
   if (startBit >= fNbits) return fNbits;
   UInt_t startByte = startBit/8;
   UInt_t ibit = startBit%8;
   if (ibit) {
      for (i=ibit;i<8;i++) {
         if ((fAllBits[startByte] & (1<<i)) == 0) return 8*startByte+i;
      }
      startByte++;
   }
   for(i=startByte; i<fNbytes; i++) {
      if (fAllBits[i] != 255) return 8*i + fbits[fAllBits[i]];
   }
   return fNbits;
}

//______________________________________________________________________________
UInt_t TBits::FirstSetBit(UInt_t startBit) const
{
   // Return position of first non null bit

   const Int_t fbits[256] = {
             8,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,
             4,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,
             5,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,
             4,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,
             6,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,
             4,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,
             5,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,
             4,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,
             7,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,
             4,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,
             5,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,
             4,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,
             6,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,
             4,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,
             5,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,
             4,0,1,0,2,0,1,0,3,0,1,0,2,0,1,0};

   UInt_t i;
   if (startBit == 0) {
      for(UInt_t i=0; i<fNbytes; i++) {
         if (fAllBits[i] != 0) return 8*i + fbits[fAllBits[i]];
      }
      return fNbits;
   }
   if (startBit >= fNbits) return fNbits;
   UInt_t startByte = startBit/8;
   UInt_t ibit = startBit%8;
   if (ibit) {
      for (i=ibit;i<8;i++) {
         if ((fAllBits[startByte] & (1<<i)) != 0) return 8*startByte+i;
      }
      startByte++;
   }
   for(i=startByte; i<fNbytes; i++) {
      if (fAllBits[i] != 0) return 8*i + fbits[fAllBits[i]];
   }
   return fNbits;
}

//______________________________________________________________________________
void TBits::Paint(Option_t *)
{
   // Once implemented, it will draw the bit field as an histogram.
   // use the TVirtualPainter as the usual trick

}

//______________________________________________________________________________
void TBits::Print(Option_t *) const
{
   // Print the list of active bits

   Int_t count = 0;
   for(UInt_t i=0; i<fNbytes; i++) {
      UChar_t val = fAllBits[i];
      for (UInt_t j=0; j<8; j++) {
         if (val & 1) printf(" bit:%4d = 1\n",count);
         count++;
         val = val >> 1;
      }
   }
}

//______________________________________________________________________________
void TBits::ResetAllBits(Bool_t)
{
   // Reset all bits to 0 (false).

   if (fAllBits) memset(fAllBits,0,fNbytes);
}

//______________________________________________________________________________
void TBits::SetBitNumber(UInt_t bitnumber, Bool_t value)
{
   // Set bit number 'bitnumber' to be value

   if (bitnumber >= fNbits) {
      UInt_t new_size = (bitnumber/8) + 1;
      if (new_size > fNbytes) {
         UChar_t *old_location = fAllBits;
         fAllBits = new UChar_t[new_size];
         if (old_location) {
            memcpy(fAllBits,old_location,fNbytes);
            delete [] old_location;
         }
         memset(fAllBits+fNbytes ,0, new_size-fNbytes);
         fNbytes = new_size;
      }
      fNbits = bitnumber+1;
   }
   UInt_t  loc = bitnumber/8;
   UChar_t bit = bitnumber%8;
   if (value)
      fAllBits[loc] |= (1<<bit);
   else
      fAllBits[loc] &= (0xFF ^ (1<<bit));
}

//______________________________________________________________________________
Bool_t TBits::TestBitNumber(UInt_t bitnumber) const
{
   // Return the current value of the bit

   if (bitnumber >= fNbits) return kFALSE;
   UInt_t  loc = bitnumber/8;
   UChar_t value = fAllBits[loc];
   UChar_t bit = bitnumber%8;
   Bool_t  result = (value & (1<<bit)) != 0;
   return result;
   // short: return 0 != (fAllBits[bitnumber/8] & (1<< (bitnumber%8)));
}

