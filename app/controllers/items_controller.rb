class ItemsController < ApplicationController
  before_action :set_item, only: %i[show edit update destroy reupload_image]

  # GET /items or /items.json
  def index
    @total_items = Item.sum('quantity')
    @total_cost = Item.sum('cost_price * quantity').round(2)
    @total_selling = Item.sum('selling_price * quantity').round(2)
    @total_profit = (@total_selling - @total_cost).round(2)

    # Unlisted counts for stat cards
    @unlisted_counts = {
      takealot:    Item.where(listed_on_takealot: false).count,
      woocommerce: Item.where(listed_on_woocommerce: false).count,
      amazon:      Item.where(listed_on_amazon: false).count,
      zoho:        Item.where(listed_on_zoho: false).count
    }

    # Platform filter
    @active_filter = params[:platform]
    @items = case @active_filter
             when 'takealot'    then Item.where(listed_on_takealot: false)
             when 'woocommerce' then Item.where(listed_on_woocommerce: false)
             when 'amazon'      then Item.where(listed_on_amazon: false)
             when 'zoho'        then Item.where(listed_on_zoho: false)
             else Item.all
             end
    @items = @items.order(id: :desc)

    # Last sync time and platform sync service statuses
    @last_synced_at = Item.maximum(:last_synced_at)
    @platform_statuses = PlatformSetting.all_statuses
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

  def google_scan
    # Renders the google scanner view
  end

  def lookup_google
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

    data = GoogleBarcodeService.new(barcode).fetch_item_data

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

  def sync_images
    results = { success: 0, failed: 0, skipped: 0, errors: [] }

    Item.where.not(image: [nil, '']).each do |item|
      if File.exist?("public/assets/#{item.id}.jpg")
        results[:skipped] += 1
        next
      end

      item.upload_image(item)
      results[:success] += 1
    rescue StandardError => e
      results[:failed] += 1
      results[:errors] << "Item ##{item.id}: #{e.message}"
    end

    respond_to do |format|
      format.html { redirect_to items_url, notice: "Sync complete: #{results[:success]} uploaded, #{results[:skipped]} skipped, #{results[:failed]} failed." }
      format.json { render json: results }
    end
  end

  def reupload_image
    @item.force_upload_image
    respond_to do |format|
      format.html { redirect_to edit_item_path(@item), notice: 'Image re-uploaded to Cloudinary.' }
      format.json { render json: { success: true } }
    end
  rescue StandardError => e
    respond_to do |format|
      format.html { redirect_to edit_item_path(@item), alert: "Image upload failed: #{e.message}" }
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  # ============================================================================
  # POST /items/sync_platform
  #
  # Triggers a background sync job for one or all platforms.
  # Params:
  #   - platform: 'takealot' | 'woocommerce' | 'amazon' | 'all' (default: 'all')
  # ============================================================================
  def sync_platform
    # Step 1: Sanitize and validate target platform name
    requested_platform = params[:platform].to_s.downcase.presence || 'all'
    allowed_platforms  = SyncPlatformStockJob::PLATFORM_SERVICES.keys + ['all']
    platform           = allowed_platforms.include?(requested_platform) ? requested_platform : 'all'

    # Step 2: Guard check - if targeting a specific platform that is disabled, alert the user
    if platform != 'all' && !PlatformSetting.enabled?(platform)
      label = platform.capitalize
      respond_to do |format|
        format.html { redirect_to items_url, alert: "#{label} sync service is currently disabled. Please enable it using the toggle first." }
        format.json { render json: { error: "#{label} sync service is disabled" }, status: :unprocessable_entity }
      end
      return
    end

    # Step 3: Enqueue the background sync job via Sidekiq
    SyncPlatformStockJob.perform_later(platform)

    # Step 4: Respond to browser (redirect) or API caller (JSON)
    label = platform == 'all' ? 'all platforms' : platform.capitalize
    respond_to do |format|
      format.html { redirect_to items_url, notice: "Sync started for #{label}. Check back in a moment." }
      format.json { render json: { status: 'queued', platform: platform } }
    end
  end

  # ============================================================================
  # POST /items/toggle_platform_sync
  #
  # Toggles the enabled/disabled state of a platform sync service.
  # Params:
  #   - platform: 'takealot' | 'woocommerce' | 'amazon' | 'zoho'
  # ============================================================================
  def toggle_platform_sync
    # Step 1: Sanitize target platform
    platform = params[:platform].to_s.downcase.strip

    # Step 2: Toggle status in PlatformSetting
    new_state = PlatformSetting.toggle!(platform)
    label = platform.capitalize
    status_text = new_state ? 'enabled' : 'disabled'

    # Step 3: Respond with notice
    respond_to do |format|
      format.html { redirect_to items_url, notice: "#{label} sync service #{status_text}." }
      format.json { render json: { success: true, platform: platform, enabled: new_state } }
    end
  rescue StandardError => e
    respond_to do |format|
      format.html { redirect_to items_url, alert: "Failed to toggle #{platform} sync: #{e.message}" }
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_item
    @item = Item.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def item_params
    params.require(:item).permit(
      :name, :description, :notes, :condition, :quantity, :external_stock, :cost_price,
      :selling_price, :image, :category, :original_price, :takealot_url, :barcode,
      :listed_on_takealot, :listed_on_woocommerce, :listed_on_amazon, :listed_on_zoho,
      :takealot_offer_id, :woocommerce_product_id, :amazon_asin, :zoho_item_id, :zoho_stock
    )
  end

  def mobile_scan_params
    params.require(:item).permit(
      :name, :description, :notes, :condition, :quantity, :external_stock, :cost_price,
      :selling_price, :image, :category, :original_price, :takealot_url, :barcode,
      :listed_on_takealot, :listed_on_woocommerce, :listed_on_amazon, :listed_on_zoho,
      :takealot_offer_id, :woocommerce_product_id, :amazon_asin, :zoho_item_id, :zoho_stock
    )
  end
end
