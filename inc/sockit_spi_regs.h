////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  SPI (3 wire, dual, quad) master                                           //
//                                                                            //
//  Copyright (C) 2011  Iztok Jeras                                           //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//  This RTL is free hardware: you can redistribute it and/or modify          //
//  it under the terms of the GNU Lesser General Public License               //
//  as published by the Free Software Foundation, either                      //
//  version 3 of the License, or (at your option) any later version.          //
//                                                                            //
//  This RTL is distributed in the hope that it will be useful,               //
//  but WITHOUT ANY WARRANTY; without even the implied warranty of            //
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the             //
//  GNU General Public License for more details.                              //
//                                                                            //
//  You should have received a copy of the GNU General Public License         //
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.     //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

#ifndef __SOCKIT_SPI_REGS_H__
#define __SOCKIT_SPI_REGS_H__

#include <io.h>

////////////////////////////////////////////////////////////////////////////////
// data register                                                              //
////////////////////////////////////////////////////////////////////////////////

#define SOCKIT_SPI_DAT_REG               0
#define IOADDR_SOCKIT_SPI_DAT(base)      IO_CALC_ADDRESS_NATIVE(base, SOCKIT_SPI_DAT_REG)
#define IORD_SOCKIT_SPI_DAT(base)        IORD(base, SOCKIT_SPI_DAT_REG)
#define IOWR_SOCKIT_SPI_DAT(base, data)  IOWR(base, SOCKIT_SPI_DAT_REG, data)

////////////////////////////////////////////////////////////////////////////////
// control status register                                                    //
////////////////////////////////////////////////////////////////////////////////

#define SOCKIT_SPI_CTL_REG               1
#define IOADDR_SOCKIT_SPI_CTL(base)      IO_CALC_ADDRESS_NATIVE(base, SOCKIT_SPI_CTL_REG)
#define IORD_SOCKIT_SPI_CTL(base)        IORD(base, SOCKIT_SPI_CTL_REG)
#define IOWR_SOCKIT_SPI_CTL(base, data)  IOWR(base, SOCKIT_SPI_CTL_REG, data)

#define SOCKIT_SPI_CTL_DAT_MSK           (0x00000001)  // data bit
#define SOCKIT_SPI_CTL_DAT_OFST          (0)


// common commands

////////////////////////////////////////////////////////////////////////////////
// SPI configuration register                                                 //
////////////////////////////////////////////////////////////////////////////////

#define SOCKIT_SPI_CFG_REG               3
#define IOADDR_SOCKIT_SPI_CFG(base)      IO_CALC_ADDRESS_NATIVE(base, SOCKIT_SPI_CFG_REG)
#define IORD_SOCKIT_SPI_CFG(base)        IORD(base, SOCKIT_SPI_CFG_REG)
#define IOWR_SOCKIT_SPI_CFG(base, data)  IOWR(base, SOCKIT_SPI_CFG_REG, data)

////////////////////////////////////////////////////////////////////////////////
// SPI configuration register                                                 //
////////////////////////////////////////////////////////////////////////////////

#define SOCKIT_SPI_XIP_REG               3
#define IOADDR_SOCKIT_SPI_XIP(base)      IO_CALC_ADDRESS_NATIVE(base, SOCKIT_SPI_XIP_REG)
#define IORD_SOCKIT_SPI_XIP(base)        IORD(base, SOCKIT_SPI_XIP_REG)
#define IOWR_SOCKIT_SPI_XIP(base, data)  IOWR(base, SOCKIT_SPI_XIP_REG, data)

#endif /* __SOCKIT_SPI_REGS_H__ */
