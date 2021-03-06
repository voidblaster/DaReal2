/+
    This file is part of DaReal².
    Copyright (c) 2018  0xEAB

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
 +/
/++
    Memory-intensive matrix-based collision detection

    The idea is to create matrix containing a simplified projection of game world's block data.
    This allows to allows to query the matrix instead of iterating over the blocks every check.
    In order to reduce the memory usage one might consider splitting the whole block data
    into seperate collision domains.

    This does not support negative positions.
 +/
module dareal.platformer.matrixcollider;

import std.container.array : Array;
import std.range : ElementType;
import dareal.platformer.world;

public
{
    import std.range : Chunks;
}

public
{
    alias MatrixBase = Array!bool.Range;
    alias Matrix = Chunks!MatrixBase;
}

/++
    Data and meta data container for matrix-based collision detection
 +/
struct MatrixCollider
{
@safe pure nothrow @nogc:

    /++
        Size of a tile in the matrix
     +/
    size_t tileSize = 1;

    /++
        Width of the world projected onto the matrix
     +/
    size_t realWidth;

    /++
        Height of the world projected onto the matrix
     +/
    size_t realHeight;

    /++
        Width of the matrix projection
     +/
    @property size_t projectionWidth() const
    {
        return (this.realWidth / this.tileSize);
    }

    /++
        Height of the matrix projection
     +/
    @property size_t projectionHeight() const
    {
        return (this.realHeight / this.tileSize);
    }
}

/++
    Creates a new matrix and fills it with blocks data;
 +/
Matrix buildMatrix(Range)(MatrixCollider mxcr, Range blocks)
        if (hasPosition!(ElementType!Range))
{
    auto m = mxcr.newMatrix();
    mxcr.fillMatrix(m, blocks);
    return m;
}

/++
    Fills the collision matrix based on the passed blocks

    See_Also:
        insertMatrix() for single blocks
 +/
void fillMatrix(Matrix2D, Range)(MatrixCollider mxcr, Matrix2D matrix, Range blocks)
        if (isBlockType!(ElementType!Range))
{
    pragma(inline, true);
    foreach (block; blocks)
    {
        mxcr.insertMatrix(matrix, block);
    }
}

/++
    Adds the passed block to the collision matrix

    See_Also:
        fillMatrix() for multiple blocks at once
 +/
void insertMatrix(Matrix2D, Block)(MatrixCollider mxcr, Matrix2D matrix, Block block)
        if (isBlockType!Block)
{
    pragma(inline, true);
    mxcr.insertMatrix(matrix, block.position.x, block.position.y,
            block.size.width, block.size.height);
}

/++
    Flags a block in the collision matrix
 +/
void insertMatrix(Matrix2D)(MatrixCollider mxcr, Matrix2D matrix,
        size_t blockPositionX, size_t blockPositionY, size_t blockWidth, size_t blockHeight)
{

    pragma(inline, true);
    immutable size_t aX = blockPositionX / mxcr.tileSize;
    immutable size_t aY = blockPositionY / mxcr.tileSize;

    immutable size_t bX = (blockPositionX + blockWidth) / mxcr.tileSize - 1;
    immutable size_t bY = (blockPositionY + blockHeight) / mxcr.tileSize - 1;

    for (size_t y = aY; y < bY; ++y)
    {
        for (size_t x = aX; x < bX; ++x)
        {
            matrix[y][x] = true;
        }
    }
}

/++
    Creates a new matrix with the specified size
 +/
Matrix newMatrix(MatrixCollider mxcr) nothrow
{
    pragma(inline, true);
    return newMatrix(mxcr.projectionWidth, mxcr.projectionHeight);
}

/++ ditto +/
Matrix newMatrix(size_t matrixWidth, size_t matrixHeight) nothrow
{
    import std.range : chunks;

    auto n = matrixWidth * matrixHeight;

    Array!bool m;
    m.reserve(n);

    for (; n > 0; --n)
    {
        m ~= false;
    }

    return chunks(m[], matrixWidth);
}

/++
    Scan procedures for collision detections
 +/
enum ScanProcedure
{
    /++
        Basic "foreach" scanning
        - row by row, one coll after another

        Example:
            [3x3]
            (0/0), (0/1), (0/2), (1/0), (1/1), ...
     +/
    rowByRow,

    /++
        Complex approach checking corners first
        - row by row - from the outside in,
        from left to the center
        and from right to the center

        Overhead: 4 counters

        Odd sizes will result in duplicated checks.
        Results will be slow if the collision happens somewhere in the middle.
        Moreover, this will be rather slow if there's no collision.

        Example:
            [2x5]                       // <-- odd height

            center := (1+0)/2 = 0
            middle := (4+0)/2 = 2

            (0/0), (1/4), (1/0), (0/4)
            (0/1), (1/3), (1/1), (0/3)
            (0/2), (1/2), (1/2), (0/2)  // <-- duplicates

            --> up to 4x3 checks in this example

        -----------------------------------------------------------

            [4x4]                       // <-- both even, best case

            center := (3+0)/2 = 1
            middle := (3+0)/2 = 1

            (0/0), (3/3), (3/0), (0/3)
            (1/0), (2/3), (2/0), (1/3)
            (0/1), (3/2), (3/1), (0/2)
            (1/1), (2/2), (2/1), (1/2)

            --> up to 4x4 checks in this example

        -----------------------------------------------------------

        Example:
            [5x5]                       // <-- both odd, worst case

            center := (4+0)/2 = 2
            middle := (4+0)/2 = 2

            (0/0), (4/4), (4/0), (0/4)
            (1/0), (3/4), (3/0), (1/4)
            (2/0), (2/4), (2/0), (2/4)  // <-- duplicates
            (0/1), (4/3), (4/1), (0/3)
            (1/1), (3/3), (3/1), (1/3)
            (2/1), (2/3), (2/1), (2/3)  // <-- duplicates
            (0/2), (4/2), (4/2), (0/2)  // <-- duplicates
            (1/2), (3/2), (3/2), (1/2)
            (2/2), (2/2), (2/2), (2/2)  // <-- duplicates

            --> up to 9x4 checks in this example
     +/
    topLeftBottomRight,

    /++
        Quick scan that will only check the outer rectangle

        Example:
            [5x4]
            (4/3), (3/3), (2/3), (1/3), // <-- bottom
            (0/0), (1/0), (2/0), (3/0), // <-- top
            (4/0), (4/1), (4/2),        // <-- right
            (0/3), (0/2), (0/1),        // <-- left
     +/
    borderOnly,

    /++
        Quick scan that will only process the bottom border

        Example:
            [5x4]
            (0/3), (1/3), (2/3), (3/3), (4/3)
     +/
    borderBottomOnly,

    /++
        Quick scan that will only process the left border

        Example:
            [5x4]
            (0/0), (0/1), (0/2), (0/3)
     +/
    borderLeftOnly,

    /++
        Quick scan that will only process the right border

        Example:
            [5x4]
            (4/0), (4/1), (4/2), (4/3)
     +/
    borderRightOnly,

    /++
        Quick scan that will only process the top border

        Example:
            [5x4]
            (0/0), (1/0), (2/0), (3/0), (4/0)
     +/
    borderTopOnly,

    /++
        Quick scan that will only process the corners

        Example:
            [5x5]
            (0/0), (4/4), (0/4), (4/0)
     +/
    cornersOnly,

    /++
        Single column scan that will only process the top left corner

        Example:
            [5x5]
            (0/0)
     +/
    cornerTopLeftOnly,

    /++
        Single column scan that will only process the top right corner

        Example:
            [5x5]
            (4/0)
     +/
    cornerTopRightOnly,

    /++
        Single column scan that will only process the bottom left corner

        Example:
            [5x5]
            (0/4)
     +/
    cornerBottomLeftOnly,

    /++
        Single column scan that will only process the bottom right corner

        Example:
            [5x5]
            (4/4)
     +/
    cornerBottomRightOnly,

    /++
        Dual column scan that will only process the top pair of corners

        Example:
            [5x5]
            (0/0), (4/0)
     +/
    cornersTopOnly,

    /++
        Dual column scan that will only process the bottom pair of corners

        Example:
            [5x5]
            (0/4), (4/4)
     +/
    cornersBottomOnly,

    /++
        Dual column scan that will only process the left pair of corners

        Example:
            [5x5]
            (0/0), (0/4)
     +/
    cornersLeftOnly,

    /++
        Dual column scan that will only process the right pair of corners

        Example:
            [5x5]
            (4/0), (4/4)
     +/
    cornersRightOnly,
}

/++
    Determines whether a collision occures for the passed block
 +/
bool collide(ScanProcedure scanProcedure = ScanProcedure.rowByRow, Matrix2D, Block)(
        MatrixCollider mxcr, Matrix2D matrix, Block block) if (isBlockType!Block)
{
    pragma(inline, true);
    return mxcr.collide(matrix, block.position.x, block.position.y,
            block.size.width, block.size.height);
}

/++ ditto +/
bool collide(ScanProcedure scanProcedure = ScanProcedure.rowByRow, Matrix2D)(MatrixCollider mxcr, Matrix2D matrix,
        size_t blockPositionX, size_t blockPositionY, size_t blockWidth, size_t blockHeight)
{
    // dfmt off
    static if (scanProcedure != ScanProcedure.borderRightOnly
            && scanProcedure != ScanProcedure.cornerBottomRightOnly
            && scanProcedure != ScanProcedure.cornerTopRightOnly
            && scanProcedure != ScanProcedure.cornersRightOnly)
    {
        immutable size_t aX = blockPositionX / mxcr.tileSize;
    }

    static if (scanProcedure != ScanProcedure.borderBottomOnly
            && scanProcedure != ScanProcedure.cornerBottomLeftOnly
            && scanProcedure != ScanProcedure.cornerBottomRightOnly
            && scanProcedure != ScanProcedure.cornersBottomOnly)
    {
        immutable size_t aY = blockPositionY / mxcr.tileSize;
    }

    static if (scanProcedure != ScanProcedure.borderLeftOnly
            && scanProcedure != ScanProcedure.cornerBottomLeftOnly
            && scanProcedure != ScanProcedure.cornerTopLeftOnly
            && scanProcedure != ScanProcedure.cornersLeftOnly)
    {
        immutable size_t bX = (blockPositionX + blockWidth) / mxcr.tileSize - 1;
    }

    static if (scanProcedure != ScanProcedure.borderTopOnly
            && scanProcedure != ScanProcedure.cornerTopLeftOnly
            && scanProcedure != ScanProcedure.cornerTopRightOnly
            && scanProcedure != ScanProcedure.cornersTopOnly)
    {
        immutable size_t bY = (blockPositionY + blockHeight) / mxcr.tileSize - 1;
    }
    // dfmt on

    static if (scanProcedure == ScanProcedure.rowByRow)
    {
        for (size_t y = aY; y <= bY; ++y)
        {
            for (size_t x = aX; x <= bX; ++x)
            {
                if (matrix[y][x])
                {
                    return true;
                }
            }
        }

        return false;
    }
    else static if (scanProcedure == ScanProcedure.topLeftBottomRight)
    {
        immutable size_t y05 = (bY + aY) / 2;
        immutable size_t x05 = (bX + aX) / 2;

        size_t x1 = aX;
        size_t x2 = bX;
        size_t y1 = aY;
        size_t y2 = bY;

        while (true)
        {
            if (matrix[y1][x1] || matrix[y2][x2] || matrix[y1][x2] || matrix[y2][x1])
            {
                return true;
            }

            if (x1 < x05)
            {
                ++x1;
            }
            else if (x1 == x05)
            {
                if (y1 < y05)
                {
                    ++y1;
                }
                else if (y1 == y05)
                {
                    return false;
                }

                if (y2 > y05)
                {
                    --y2;
                }

                x1 = aX;
                x2 = bX;
                continue;
            }

            if (x2 > x05)
            {
                --x2;
            }
        }

        return false;
    }
    else static if (scanProcedure == ScanProcedure.borderOnly)
    {
        for (size_t x = bX; x > aX; --x)
        {
            if (matrix[bY][x])
            {
                return true;
            }
        }

        for (size_t x = aX; x < bX; ++x)
        {
            if (matrix[aY][x])
            {
                return true;
            }
        }

        for (size_t y = aY; y < bY; ++y)
        {
            if (matrix[y][bX])
            {
                return true;
            }
        }

        for (size_t y = bY; y > 0; --y)
        {
            if (matrix[y][aX])
            {
                return true;
            }
        }

        return false;
    }
    else static if (scanProcedure == ScanProcedure.borderBottomOnly)
    {
        for (size_t x = aX; x <= bX; ++x)
        {
            if (matrix[bY][x])
            {
                return true;
            }
        }

        return false;
    }
    else static if (scanProcedure == ScanProcedure.borderLeftOnly)
    {
        for (size_t y = aY; y <= bY; ++y)
        {
            if (matrix[y][aX])
            {
                return true;
            }
        }

        return false;
    }
    else static if (scanProcedure == ScanProcedure.borderRightOnly)
    {
        for (size_t y = aY; y <= bY; ++y)
        {
            if (matrix[y][bX])
            {
                return true;
            }
        }

        return false;
    }
    else static if (scanProcedure == ScanProcedure.borderTopOnly)
    {
        for (size_t x = aX; x <= bX; ++x)
        {
            if (matrix[aY][x])
            {
                return true;
            }
        }

        return false;
    }
    else static if (scanProcedure == ScanProcedure.cornersOnly)
    {
        pragma(inline, true);
        return (matrix[aY][aX] || matrix[bY][bX] || matrix[aY][bX] || matrix[bY][aX]);
    }
    else static if (scanProcedure == ScanProcedure.cornerTopLeftOnly)
    {
        pragma(inline, true);
        return (matrix[aY][aX]);
    }
    else static if (scanProcedure == ScanProcedure.cornerTopRightOnly)
    {
        pragma(inline, true);
        return (matrix[aY][bX]);
    }
    else static if (scanProcedure == ScanProcedure.cornerBottomLeftOnly)
    {
        pragma(inline, true);
        return (matrix[bY][aX]);
    }
    else static if (scanProcedure == ScanProcedure.cornerBottomRightOnly)
    {
        pragma(inline, true);
        return (matrix[bY][bX]);
    }
    else static if (scanProcedure == ScanProcedure.cornersTopOnly)
    {
        pragma(inline, true);
        return (matrix[aY][aX] || matrix[aY][bX]);
    }
    else static if (scanProcedure == ScanProcedure.cornersBottomOnly)
    {
        pragma(inline, true);
        return (matrix[bY][aX] || matrix[bY][bX]);
    }
    else static if (scanProcedure == ScanProcedure.cornersLeftOnly)
    {
        pragma(inline, true);
        return (matrix[aY][aX] || matrix[bY][aX]);
    }
    else static if (scanProcedure == ScanProcedure.cornersRightOnly)
    {
        pragma(inline, true);
        return (matrix[aY][bX] || matrix[bY][bX]);
    }
    else
    {
        import std.conv : to;

        static assert(0, "No implementation for scan procedure: " ~ scanProcedure.to!string);
    }
}

/++
    Collision matrices collection

    See_Also:
        Use .buildMatrices() for construction
 +/
struct WorldMatrices
{
    /++
        Collision matrix for wall blocks
     +/
    Matrix walls;

    /++
        Collision matrix for jump-through blocks
     +/
    Matrix jumpThroughBlocks;
}

/++
    Creates the collision matrices for the passed world
 +/
WorldMatrices buildMatrices(RangeWall, RangeJumpThrough)(MatrixCollider mxcr,
        RangeWall wallBlocks, RangeJumpThrough jumpThroughBlocks)
        if (isBlockType!(ElementType!RangeWall) && isBlockType!(ElementType!RangeJumpThrough))
{
    pragma(inline, true);
    return WorldMatrices(mxcr.buildMatrix(wallBlocks), mxcr.buildMatrix(jumpThroughBlocks));
}
