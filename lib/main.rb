# A game is a board
#
# The game is created by the app. The game creates the board, performs updates
# for the app and updates the app.
#
#
class Game
  attr_reader :app, :board
  attr_accessor :score, :score_text

  def initialize(app)
    @app   = app
    
    setup_board

    # wait with setting up the score until the board has finished setup
    @score = 0
    @score_text = @app.para("Score: #{@score}", :top => 5, :left => 5)
  end

  # Make a nice little Board object
  #
  def setup_board
    @app.background @app.white
    @app.stroke @app.white
    @board = Board.new(self)
  end

  # Update the game (ea; update the board)
  #
  def update
    board.update
  end

  # update the score and update the score text on the app
  #
  def update_score_by(amount)
    if score
      self.score = score + amount
    end
    if score_text
      self.score_text.replace "Score: #{score}"
    end
  end
end # / Game

class Board
  WIDTH  = 8
  HEIGHT = 8

  attr_reader :game, :width, :height
  
  def initialize(game, width=WIDTH, height=HEIGHT)
    @game   = game
    @width  = width
    @height = height
    
    setup_pieces
    init_listeners
    
    draw
  end

  # place new pieces in an array of columns and rows on the board
  #
  # make sure there are no matches and there are moves left
  #
  def setup_pieces
    @pieces ||= Array.new(width) { Array.new(height) { nil } }

    @pieces = @pieces.each_index { |col|
      @pieces[col].each_index { |row|
        @pieces[col][row] ||= Piece.new(self, col, row)
      }
    }

    while has_matches?
      clear_matches
      setup_pieces
    end

    if !moves_left?
      @pieces = nil
      setup_pieces
    end
  end

  # set up listeners
  #
  def init_listeners
    game.app.click do |button, x, y|
      if selected.nil?
        # when no piece is selected, select one
        select(x,y)

      else
        # otherwise; swap the pieces if they are adjecent,
        # select a new piece if not
        #
        other = pieces.select { |piece| piece.placed_on?(x,y) }.first
        puts "No other..." if other.nil?

        if ( [-1, 0, 1 ].include?(other.x - selected.x) and
             [-1, 0, 1 ].include?(other.y - selected.y)
        ) then
          # when it is a seemingly valid move, swap the selected ones
          unless swap_selected(other)
            other.select
          end

        else
          # when not; select a new piece
          select(x,y)

        end
      end
    end
  end
  
  # Update the pieces on the board
  #
  # + When there are moveable pieces, move them
  # + When there are matches, clear them
  # + When there are empty pieces, drop in new ones.
  # + Check if there are moves left
  # + Redraw the board
  #
  def update
    if moveable_pieces?
      move_pieces

    else
      # clear matches
      if has_matches?
        clear_matches
        
      else
        # and drop in new pieces while there are empty pieces
        unless pieces.select { |piece| piece.nil? or !piece.is_a? Piece }.empty?
          drop_pieces
        end

        moves_left?
      end
    end
    
    # redraw unless moveable_pieces?
  end

  # return all the pieces on the board as a single array
  #
  def pieces
    @pieces.flatten
  end

  # draw the board (that is let each piece draw)
  #
  def draw
    pieces.each { |piece| piece.draw unless piece.nil? }
  end

  # call redraw on each of the places and pieces
  #
  def redraw
    pieces.each { |piece| piece.redraw unless piece.nil? }
  end

  # select a piece for the next move and make it selected
  #
  # Also; unselect the currently selected piece
  #
  def select(x,y)
    if ( piece = selected )
      piece.unselect
      piece.redraw
    end
    
    self.pieces.each { |piece|
      piece.select if piece and piece.placed_on?(x,y)
    }
  end

  # return the selected piece
  #
  def selected
    self.pieces.select { |piece| piece and piece.selected? }.first
  end

  # swap to pieces on the board by changing their place in the array.
  # And let the pieces know they are on a different index.
  #
  def swap(one,two)
    return if one.nil? or two.nil?
    return if one == two

    # swap the pieces on the board
    @pieces[two.x][two.y] = one
    @pieces[one.x][one.y] = two

    # remember the index of the selected piece
    store_index = one.index

    # update the indexes of the piece to reflect the new places on the board
    one.index = two.index
    two.index = store_index
  end

  # swap the selected piece with an other
  #
  def swap_selected(other)
    sel = selected
    if ((other.x + other.y) - (sel.x + sel.y)).abs != 1
      sel.unselect
      sel.redraw
      return false
    end

    # swap the pieces on the board
    swap(other,sel)

    # when there are no matches, do nothing
    unless has_matches?
      swap(sel,other)      
      sel.unselect
      sel.redraw
      return false
    end

    # forget the selection
    sel.unselect

    return true
  end

  # Check if there are 3 pieces in a horizontal or vertical row.
  #
  # If there are; mark the pieces.
  #
  def has_matches?
    match = false
    # traverse rows to see if there is a string of 3+ pieces of one color
    @pieces.each_index { |col|
      break if col+2 == @pieces.length
      @pieces[col].each_index { |row|
        begin
          if (
            @pieces[col][row].color == @pieces[col+1][row].color and
            @pieces[col][row].color == @pieces[col+2][row].color
          ) then
            match = true
            3.times do |i|
              @pieces[col+i][row].mark
            end
          end
        rescue
          next
        end
      }
    }

    # traverse cols to see if there is a string of 3+ pieces of one color
    @pieces.each_index { |col|
      @pieces[col].each_index { |row|
        break if row+2 == @pieces[col].length

        begin
          if (
            @pieces[col][row].color == @pieces[col][row+1].color and
            @pieces[col][row].color == @pieces[col][row+2].color
          ) then
            match = true
            3.times do |i|
              @pieces[col][row+i].mark
            end
          end
        rescue
          next
        end
      }
    }

    return match
  end

  # clear any matching pieces (after moving was performed)
  #
  # For each cleared piece update the score
  #
  def clear_matches
    # let the moves take place first
    return if moveable_pieces?
    return if !marked_pieces?
    
    marked_pieces.each { |piece|
      if piece and piece.marked?
        piece.remove

        game.update_score_by( 10 * piece.marked )
        @pieces[piece.x][piece.y] = nil
      end
    }
  end

  # Drop pieces when their bottom neighbour was removed due to a match.
  #
  # Also; drop in new pieces on the top row
  #
  def drop_pieces
    # let the moves unfold
    return if moveable_pieces?
    return if marked_pieces?
    
    @pieces.each_index { |col|
      @pieces[col].each_index { |row|
        next if row == HEIGHT - 1
        piece = @pieces[col][row]

        # when there is no bottom neighbour, drop this piece and
        # all the pieces above it
        #
        dist = 0
        if piece and @pieces[col][row+1].nil?
          (row+1).upto(@pieces[col].length) do |i|
            if @pieces[col][i].nil?
              dist = dist + 1
            else
              break
            end
          end

          pieces = []
          row.downto(0) do |i|
            next if @pieces[col][i].nil?
            pieces << @pieces[col][i]
          end

          pieces.each { |drop|
            while (drop.y + dist) > @pieces[col].length - 1
              dist -= 1
            end
            
            @pieces[drop.x][drop.y] = nil
            @pieces[drop.x][drop.y + dist] = drop
            drop.index = [ drop.x, drop.y + dist ]
          }
        end


        # replacements?
        if dist > 1
          # drop in replacements to fill up the drop distance
          dist.downto(1) do |i|
            place = 0 - (i+1)
            drop  = (dist-i).abs
            piece = Piece.new(self,col,place)
            piece.draw
            piece.index[1] = drop
            @pieces[col][drop] = piece
          end

        elsif ( !piece and row == 0 )
          # on the first row, drop in a piece from row -1
          piece = Piece.new(self,col,-1)
          piece.draw
          piece.index[1] = 0
          @pieces[col][0] = piece
          
        end
      }
    }

    # redraw
  end

  # move all the pieces into their required position
  #
  def move_pieces
    moveable_pieces.each { |piece|
      piece.move
    }
  end

  # get all the pieces that are moveable
  #
  def moveable_pieces
    pieces.select { |piece| piece and piece.moveable? }
  end

  # are there any moveable pieces?
  #
  def moveable_pieces?
    !moveable_pieces.empty?
  end

  # get all the pieces that are marked
  #
  def marked_pieces
    pieces.select { |piece| piece and piece.marked? }
  end

  # are there any marked pieces?
  #
  def marked_pieces?
    !marked_pieces.empty?
  end

  # Are there any moves left?
  #
  # swap each piece on the bord rightward and downward and check for matches.
  #
  # If there are matches, unmark all pieces and return
  # When there are no matches; display a warning and leave the game
  #
  # Dont perform the trick if there are moveable or marked pieces
  #
  def moves_left?
    return true if moveable_pieces?
    return true if marked_pieces?

    match = false
    @pieces.each_index { |col|
      @pieces.each_index { |row|
        this   = @pieces[col][row]

        if row+1 < @pieces[col].length
          bottom = @pieces[col][row+1]

          swap(this, bottom)
          if has_matches?
            match = true
          end
          swap(bottom, this)
        
          break if match == true
        end

        if col+1 < @pieces.length
          left   = @pieces[col+1][row]
          swap(this, left)
          if has_matches?
            match = true
          end
          swap(left, this)
        end
      }
      
      break if match == true
    }

    if match == true
      marked_pieces.each { |piece| piece.unmark }
    else
      game.alert("No more moves...")
      game.exit
    end

    return match
  end
end

# A piece has a color and a X & Y position on the board
#
# A piece might be marked or selected
#
class Piece
  COLORS = [
    "red", "purple", "blue", "green", "yellow", "orange", "pink", "magenta"
  ]
  SIZE    = 55
  DIST    = 11

  attr_reader :board, :color, :shape, :marked, :selected
  attr_accessor :index

  def initialize(board, x, y, color=nil)
    @board    = board
    @color    = color || COLORS[rand(COLORS.length)]
    @index    = [x, y]
    @marked   = 0
    @selected = false
  end

  # remove and then draw
  #
  def redraw
    remove if self.shape
    draw
  end

  # remove the shape from the app
  #
  def remove
    self.shape.remove
  rescue
  end

  # draw a shape on the app
  #
  def draw()
    (x, y) = index
    app.stroke(selected? ? app.black : app.white)
    app.fill(app.send(color))
    @shape = app.oval(x_pos, y_pos, SIZE)
  end

  # Is the piece placed on this position?
  #
  def placed_on?(x_pos,y_pos)
    x = ( ( x_pos - SIZE ) / SIZE )
    y = ( ( y_pos - SIZE ) / SIZE )

    [x,y] == index
  end

  # mark the piece for removal
  #
  def mark
    @marked += 1
  end

  # umark the piece
  #
  def unmark
    @marked = 0
  end

  # is the piece marked?
  #
  def marked?
    @marked > 0 ? true : false
  end

  # select the piece
  #
  def select
    @selected = true
    redraw
  end

  # unselect the piece
  #
  def unselect
    @selected = false
  end

  # Is the piece selected?
  #
  def selected?
    @selected == true ? true : false
  end

  # A link to the board, to the game to the app
  #
  def app
    board.game.app
  end

  # move the Shoes#shape until top and left match the x and y position
  # on the board
  #
  def move
    top  = shape.style[:top]
    left = shape.style[:left]

    dir_y = top < y_pos ? DIST : top == y_pos ? 0 : 0-DIST
    dir_x = left < x_pos ? DIST : left == x_pos ? 0 : 0-DIST

    self.shape.move(left + dir_x, top + dir_y)
  end

  # is the Shoes#shape top not on the y_pos and and the left not on the y_pos
  # then the piece is moveable
  #
  def moveable?
    return !( shape.style[:top] == y_pos and shape.style[:left] == x_pos )
  rescue
    false
  end

  # The x position on the board
  def x
    index[0]
  end

  # the y position on the board
  def y
    index[1]
  end

  # the x position on the app
  def x_pos
    SIZE + ( SIZE * index[0] )
  end

  # the y position on the app
  def y_pos
    SIZE + ( SIZE * index[1] )
  end
end

Shoes.app(
  :title  => "A Game of Shoes",
  :width  => ( Board::WIDTH + 2  ) * Piece::SIZE,
  :height => ( Board::HEIGHT + 2 ) * Piece::SIZE
) do

  game = Game.new(self)
  @anim = animate(36) do
    game.update
  end
end