class ItemsController < ApplicationController
  before_action :set_item, only: %i[show edit update destroy]

  # GET /items or /items.json
  def index
    @total_items = Item.sum('quantity')
    @total_cost = Item.sum('cost_price * quantity').round(2)
    @total_selling = Item.sum('selling_price * quantity').round(2)
    @total_profit = (@total_selling - @total_cost).round(2)
    @items = Item.all.order(:id).reverse
    # @items = Item.where('quantity > ?', 0).order(Arel.sql('cost_price * quantity DESC'))
  end

  # GET /items/1 or /items/1.json
  def show; end

  # GET /items/new
  def new
    @item = Item.new
    @item.barcode = params.dig(:item, :barcode) if params.dig(:item, :barcode).present?
  end

  # GET /items/1/edit
  def edit; end

  # POST /items or /items.json
  def create
    @item = Item.new(item_params)

    respond_to do |format|
      if @item.save
        format.html { redirect_to item_url(@item), notice: 'Item was successfully created.' }
        format.json { render :show, status: :created, location: @item }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @item.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /items/1 or /items/1.json
  def update
    respond_to do |format|
      if @item.update(item_params)
        format.html { redirect_to item_url(@item), notice: 'Item was successfully updated.' }
        format.json { render :show, status: :ok, location: @item }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @item.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /items/1 or /items/1.json
  def destroy
    @item.destroy

    respond_to do |format|
      format.html { redirect_to items_url, notice: 'Item was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  def create_from_takealot
    takealot_link = params[:takealot_link]

    if takealot_link.present?
      data = TakealotService.new(takealot_link).fetch_data

      @item = Item.new(
        name: data[:name],
        description: data[:description],
        category: data[:category],
        selling_price: data[:selling_price],
        image: data[:image],
        original_price: data[:original_price],
        takealot_url: data[:takealot_url]
      )

      if @item.save
        redirect_to edit_item_path(@item), notice: 'Item was successfully created from Takealot link.'
      else
        render :new_takealot_item_form
      end
    else
      redirect_to new_takealot_item_form_path, alert: 'Takealot link cannot be blank.'
    end

    @item.upload_image(@item)
  end

  def scan_barcode
    # Renders the view with the barcode scanner
  end

  def create_from_barcode
    barcode = params[:barcode]

    return unless barcode.present?

    data = TakealotBarcodeService.new(barcode).fetch_item_data

    return redirect_to new_item_path(item: { barcode: barcode }), alert: data[:error] if data[:error]

    @item = Item.new(
      name: data[:name],
      description: data[:description],
      category: data[:category],
      selling_price: data[:selling_price],
      image: data[:image],
      original_price: data[:original_price],
      takealot_url: data[:takealot_url]
    )

    @item.save!
    @item.upload_image(@item)
    redirect_to edit_item_path(@item), notice: 'Item was successfully created from barcode.'
  end

  def mobile_scan
    # Renders the mobile scanner view
  end

  def lookup_barcode
    barcode = params[:barcode]

    unless barcode.present?
      return render json: { error: 'Barcode is required.' }, status: :unprocessable_entity
    end

    existing_item = Item.find_by(barcode: barcode)
    if existing_item
      return render json: {
        exists: true,
        item_url: item_path(existing_item)
      }, status: :ok
    end

    data = TakealotBarcodeService.new(barcode).fetch_item_data

    if data[:error]
      render json: { error: data[:error] }, status: :not_found
    else
      render json: { product: data }, status: :ok
    end
  rescue StandardError => e
    render json: { error: "Failed to fetch product data: #{e.message}" }, status: :internal_server_error
  end

  def create_from_mobile_scan
    @item = Item.new(mobile_scan_params)

    if @item.save
      # Upload image to Cloudinary in background-safe way
      @item.upload_image(@item) if @item.image.present?
      render json: { item: @item, redirect_url: edit_item_path(@item) }, status: :created
    else
      render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { error: "Failed to create item: #{e.message}" }, status: :internal_server_error
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_item
    @item = Item.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def item_params
    params.require(:item).permit(:name, :description, :condition, :quantity, :external_stock, :cost_price,
                                 :selling_price, :image, :category, :original_price, :takealot_url, :barcode)
  end

  def mobile_scan_params
    params.require(:item).permit(:name, :description, :condition, :quantity, :external_stock, :cost_price,
                                 :selling_price, :image, :category, :original_price, :takealot_url, :barcode)
  end
end
