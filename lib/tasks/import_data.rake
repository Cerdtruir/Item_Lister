namespace :import_data do
  desc 'Import data from CSV'
  task items: :environment do
    require 'csv'
    csv_file = Rails.root.join('db', 'items.csv')

    CSV.foreach(csv_file, headers: true) do |row|
      Item.create!(
        item_name: row['Name'],
        description: row['Name'],
        condition: row['Condition'],
        quantity: row['quantity'],
        cost_price: row['cost price each'],
        selling_price: row['selling price'],
        image: row['Image Link']
      )
    end

    puts 'Data imported successfully!'
  end
end
