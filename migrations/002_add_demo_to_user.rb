Sequel.migration do
  change do
    alter_table :users  do
      add_column :demo, Integer
    end
  end
end
