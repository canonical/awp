# Alt-Ergo's non-commercial licence

Alt-Ergo is an SMT prover by OCamlPro. Two Workshop SDKs written for
auto-wp, `frama-c-sdk` (Frama-C's WP) and `creusot` (Creusot,
for Rust), bundle **Alt-Ergo 2.6.4**. Neither SDK is sold.

## Which licence applies

According to Alt-Ergo's `LICENSE.md` at tag `v2.6.4`
(<https://github.com/OCamlPro/alt-ergo/blob/v2.6.4/LICENSE.md>):

- The source files and the releases on GitHub and opam are distributed
  under the **OCamlPro Non-Commercial Purpose License, version 1** (full
  text below).
- Members of the Alt-Ergo Club at the Gold level can use the same files
  under Apache-2.0.
- OCamlPro also publishes a free release under CeCILL-C v1, as the opam
  packages `alt-ergo-free`. Its latest version is 2.4.3, and both Creusot
  and Frama-C's WP set-up expect 2.6.

The SDKs get Alt-Ergo as follows:
- `creusot`: the binary `alt-ergo-v2.6.4-x86_64-linux-musl` from
  GitHub, which Creusot's installer downloads and checks against its
  sha256.
- `frama-c-sdk`: built from the opam package `alt-ergo.2.6.4`.

Both SDKs ship `LICENSE.md` and the licence text in
`share/licenses/alt-ergo/`, and their description says "research use
only".

## Questions for the Workshop team

1. Does the SDK Store accept an SDK that bundles a component under this
   licence, given that use is limited to research?
2. If it does, which notice is required: in the SDK description, in the
   store listing, or shown to the user at install time?
3. If it does not, is the expected answer to publish without Alt-Ergo and
   let users install it themselves? Z3, CVC4 and CVC5 remain in the SDKs.
4. Does Canonical, or the Workshop team, have an arrangement with
   OCamlPro, such as Alt-Ergo Club membership?

## Full text

This is the plain-text copy from the `v2.6.4` tag, `licenses/OCamlPro-Non-Commercial-License.txt`. It is reproduced as is, typos included; the PDF in the same directory has the same text.

```text
OCamlPro Non-Commercial Purpose License, version 1

Copyright 2013-2020 by OCamlPro.

All rights reserved.

-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-

You should carefully read the following terms and conditions before
using this software. Your use of the Software indicates your
acceptance of this license agreement and all terms and conditions.

You are hereby licensed to use the Software for Non-Commercial Purpose
only. Non-Commercial Purpose means the use of the Software solely for
research. Non-Commercial Purpose excludes, without limitation, any use
of the Software, as part of, or in any way in connection with a
product or service which is sold, offered for sale, licensed, leased,
loaned, or rented, or used in a profit-making context. Permission to
use, copy, modify, and distribute this compilation for Non-Commercial
Purpose is hereby granted without fee, subject to the following terms
of this license.


# Copies and Modifications

You must include the above copyright notice and this license on any
copy or modification of this compilation. Each time you redistribute
this Software, the recipient automatically receives a license to copy,
distribute or modify the Software subject to these terms and
conditions. You may not impose any further restrictions on this
Software or any derivative works beyond those restrictions herein.

You agree to use your best efforts to provide OCamlPro with any
modifications containing improvements or extensions and hereby grant
OCamlPro a perpetual, royalty-free license to use and distribute such
modifications under its own terms of licensing. You agree to notify
OCamlPro of any inquiries you have for commercial use of the Software
and/or its modifications and further agree to negotiate in good faith
with OCamlPro to license your modifications for commercial purposes.

Notices, modifications, and questions may be directed by e-mail to the
OCamlPro team at contact@ocamlpro.com.


# Commercial Use

If you desire to use the software for profit-making or commercial
purposes, you agree to negotiate in good faith a license with OCamlPro
prior to such profitmaking or commercial use. OCamlPro shall have no
obligation to grant such license to you, and may grant exclusive or
non-exclusive licenses to others. You may contact the OCamlPro team at
email address contact@ocamlpro.com to discuss commercial use.


# Governing Law

This Agreement shall be subject to French law.


# Disclaimer of Warranty

Because this software is licensed free of charge, there is no warranty
for the program. OCamlPro makes no warranty or representation that the
operation of the software in this compilation will be error-free, and
OCamlPro is under no obligation to provide any services, by way of
maintenance, update, or otherwise.

THIS SOFTWARE AND THE ACCOMPANYING FILES ARE LICENSED “AS IS” AND
WITHOUT WARRANTIES AS TO PERFORMANCE OR MERCHANTABILITY OR ANY OTHER
WARRANTIES WHETHER EXPRESSED OR IMPLIED. NO WARRANTY OF FITNESS FOR A
PARTICULAR PURPOSE IS OFFERED. THE ENTIRE RISK AS TO THE QUALITY AND
PERFORMANCE OF THE PROGRAM IS WITH YOU. SHOULD THE PROGRAM PROVE
DEFECTIVE, YOU ASSUME THE COST OF ALL NECESSARY SERVICING, REPAIR OR
CORRECTION.


# Limitation of Liability

IN NO EVENT WILL OCAMLPRO, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE PRORAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR
DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL
DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE THE PROGRAM
(INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING RENDERED
INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A FAILURE OF
THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS), EVEN IF OCAMLPRO OR
OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.


# Use of Name

Users will not use the name of OCamlPro nor any adaptation thereof in
any publicity or advertising, without the prior written consent from
OCamlPro in each case.


# END OF TERMS AND CONDITIONS

Address all correspondence regarding this license to the OCamlPro team
at email address contact@ocamlpro.com
```
